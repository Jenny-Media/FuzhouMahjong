import AVFoundation
import Combine
import SwiftUI

enum BackgroundTrack: String, CaseIterable {
    static let storageKey = "backgroundMusic.track"

    case off
    case teaHouse = "tea-house"
    case banyanNight = "banyan-night"
    case tablePulse = "table-pulse"

    var title: String {
        switch self {
        case .off: "关闭"
        case .teaHouse: "茶馆午后"
        case .banyanNight: "榕城夜色"
        case .tablePulse: "牌桌轻拍"
        }
    }

    var recording: URL? {
        guard self != .off else { return nil }
        return Bundle.main.url(forResource: rawValue, withExtension: "m4a", subdirectory: "BackgroundMusic")
    }
}

@MainActor @Observable
final class BackgroundMusic {
    static let pauseStorageKey = "backgroundMusic.paused"

    static let audioSessionNotifications: AnyPublisher<Notification, Never> = {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        let playbackChanges = center.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .merge(with: center.publisher(for: AVAudioSession.mediaServicesWereResetNotification))
        #if compiler(>=6.4)
        if #available(iOS 27, *) {
            return playbackChanges
                .merge(with: center.publisher(for: AVAudioSession.didBecomeInactiveNotification, object: session),
                       center.publisher(for: AVAudioSession.resumptionRecommendationNotification, object: session))
                .eraseToAnyPublisher()
        }
        #endif
        return playbackChanges
            .merge(with: center.publisher(for: AVAudioSession.interruptionNotification, object: session))
            .eraseToAnyPublisher()
    }()

    struct Context: Equatable {
        var track: BackgroundTrack = .off
        var isSolo = false
        var isActive = false
    }

    enum Playback: Equatable {
        case loop(BackgroundTrack)
        case preview(BackgroundTrack)
    }

    enum PlaybackResult {
        case applied
        case unavailable
        case activationRejected
    }

    private enum PlaybackPause: Equatable {
        case systemInterruption
        case untilPlaybackRequested
    }

    private enum PendingResumption {
        case retryOnRejection
        case holdAfterPreview
    }

    private(set) var playback: Playback?
    private var previewTrack: BackgroundTrack?
    private var pausedByPlayer: Bool
    private var playbackPause: PlaybackPause?
    private var isLoopUnavailable = false
    @ObservationIgnored private var context = Context()
    @ObservationIgnored private var isPracticing = false
    @ObservationIgnored private var isSettingsPresented = false
    @ObservationIgnored private let player: any BackgroundMusicPlaying
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var requestedPlayback: Playback?
    @ObservationIgnored private var isExplicitPlaybackPending = false
    @ObservationIgnored private var pendingResumption: PendingResumption?
    @ObservationIgnored private var needsImmediateStop = false
    @ObservationIgnored private var transition: Task<Void, Never>?
    @ObservationIgnored private var previewTimer: Task<Void, Never>?

    init(player: (any BackgroundMusicPlaying)? = nil, defaults: UserDefaults? = nil) {
        self.player = player ?? BackgroundMusicPlayer()
        self.defaults = defaults
        pausedByPlayer = defaults?.bool(forKey: Self.pauseStorageKey) ?? false
    }

    var isPreviewing: Bool { previewTrack != nil }
    var isLoopPaused: Bool { pausedByPlayer || playbackPause != nil || isLoopUnavailable }
    private var hasLoopContext: Bool { context.track != .off && (context.isSolo || isPracticing) }

    func toggleLoopPause() {
        pausedByPlayer = !isLoopPaused
        defaults?.set(pausedByPlayer, forKey: Self.pauseStorageKey)
        refresh(explicitlyRequested: !pausedByPlayer)
    }

    func setSettingsPresented(_ presented: Bool) {
        guard isSettingsPresented != presented else { return }
        isSettingsPresented = presented
        if !presented { clearPreview() }
        refresh()
    }

    func update(_ newContext: Context) {
        if newContext.track != context.track {
            if previewTrack != newContext.track { clearPreview() }
            isLoopUnavailable = false
        }
        context = newContext
        if context.isActive {
            refresh()
        } else {
            suspendPlayback()
        }
    }

    func setPracticing(_ practicing: Bool) {
        isPracticing = practicing
        refresh()
    }

    func togglePreview(_ track: BackgroundTrack) {
        guard context.isActive, track != .off else { return }
        if previewTrack == track {
            endPreview()
            return
        }
        clearPreview()
        previewTrack = track
        refresh()
    }

    func endPreview() {
        guard previewTrack != nil else { return }
        clearPreview()
        refresh()
    }

    func handleAudioSessionNotification(_ notification: Notification) {
        switch notification.name {
        case AVAudioSession.mediaServicesWereResetNotification:
            pauseUntilPlaybackRequested()
            return
        case AVAudioSession.routeChangeNotification:
            if let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               AVAudioSession.RouteChangeReason(rawValue: value) == .oldDeviceUnavailable,
               requestedPlayback != nil || (hasLoopContext && !pausedByPlayer) {
                pauseUntilPlaybackRequested()
            }
            return
        default:
            break
        }
        #if compiler(>=6.4)
        if #available(iOS 27, *) {
            switch notification.name {
            case AVAudioSession.didBecomeInactiveNotification:
                if let event = notification.userInfo?[AVAudioSession.deactivationContextKey]
                    as? AVAudioSession.DeactivationContext, event.source == .system {
                    systemInterruptionBegan()
                }
                return
            case AVAudioSession.resumptionRecommendationNotification:
                if let event = notification.userInfo?[AVAudioSession.resumptionContextKey]
                    as? AVAudioSession.ResumptionContext {
                    handleSystemResumption(shouldResume: event.recommendation == .shouldResume)
                }
                return
            default:
                break
            }
        }
        #endif
        guard notification.name == AVAudioSession.interruptionNotification,
              let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: value) else { return }
        switch type {
        case .began:
            systemInterruptionBegan()
        case .ended:
            let options = AVAudioSession.InterruptionOptions(
                rawValue: notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            )
            handleSystemResumption(shouldResume: options.contains(.shouldResume))
        @unknown default:
            break
        }
    }

    func systemInterruptionBegan() {
        if playbackPause == nil { playbackPause = .systemInterruption }
        suspendPlayback()
    }

    func handleSystemResumption(shouldResume: Bool) {
        guard shouldResume else {
            pendingResumption = isExplicitPlaybackPending && isPreviewing ? .holdAfterPreview : nil
            if isExplicitPlaybackPending || isPreviewing {
                // Let the explicit request continue while holding its automatic successor.
                if playbackPause == nil { playbackPause = .systemInterruption }
            } else if playback == nil, playbackPause == nil || requestedPlayback != nil {
                // A recommendation can arrive without a deactivation event.
                systemInterruptionBegan()
            }
            return
        }
        if playbackPause == .systemInterruption { playbackPause = nil }
        if requestedPlayback != nil, playback == nil {
            pendingResumption = .retryOnRejection
        }
        refresh()
    }

    private func pauseUntilPlaybackRequested() {
        playbackPause = .untilPlaybackRequested
        suspendPlayback()
    }

    private func suspendPlayback() {
        clearPreview()
        needsImmediateStop = true
        request(nil, force: true)
    }

    private func clearPreview() {
        previewTimer?.cancel()
        previewTimer = nil
        previewTrack = nil
    }

    private func refresh(explicitlyRequested: Bool = false) {
        guard context.isActive else { return }
        if let previewTrack {
            request(.preview(previewTrack), explicitlyRequested: true)
            return
        }
        let loop = Playback.loop(context.track)
        let explicitlyResuming = explicitlyRequested || (isExplicitPlaybackPending && requestedPlayback == loop)
        guard !isSettingsPresented, !pausedByPlayer, !isLoopPaused || explicitlyResuming, hasLoopContext else {
            request(nil)
            return
        }
        request(loop, explicitlyRequested: explicitlyResuming)
    }

    private func request(_ mode: Playback?, force: Bool = false, explicitlyRequested: Bool = false) {
        guard force || requestedPlayback != mode else { return }
        requestedPlayback = mode
        isExplicitPlaybackPending = explicitlyRequested
        playback = nil
        pendingResumption = nil
        transition?.cancel()
        // A replacement task must stop the old player immediately if it supersedes a suspension.
        let fadeOut = !needsImmediateStop
        transition = Task { [weak self, player] in
            let result = await player.apply(mode, fadeOut: fadeOut)
            guard !Task.isCancelled, let self else { return }
            isExplicitPlaybackPending = false
            needsImmediateStop = false
            let resumption = pendingResumption
            pendingResumption = nil
            switch result {
            case .applied:
                playback = mode
                if explicitlyRequested, mode != nil {
                    playbackPause = resumption == .holdAfterPreview ? .systemInterruption : nil
                    isLoopUnavailable = false
                }
                if case .preview = mode {
                    previewTimer = Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(10)) } catch { return }
                        guard !Task.isCancelled else { return }
                        self?.endPreview()
                    }
                }
            case .unavailable:
                requestedPlayback = nil
                if case .loop = mode { isLoopUnavailable = true }
                if previewTrack != nil { endPreview() }
            case .activationRejected:
                requestedPlayback = nil
                if resumption == .retryOnRejection {
                    refresh(explicitlyRequested: explicitlyRequested)
                } else {
                    systemInterruptionBegan()
                }
            }
        }
    }
}

protocol BackgroundMusicPlaying: Actor {
    func apply(_ mode: BackgroundMusic.Playback?, fadeOut: Bool) async -> BackgroundMusic.PlaybackResult
}

// Audio session setup and file playback can block. The player owns them off the UI actor.
private actor BackgroundMusicPlayer: BackgroundMusicPlaying {
    private static let fade = 0.24
    private var player: AVAudioPlayer?
    private var loopTrack: BackgroundTrack?
    private var loopPosition: (track: BackgroundTrack, time: TimeInterval)?

    func apply(_ mode: BackgroundMusic.Playback?, fadeOut: Bool) async -> BackgroundMusic.PlaybackResult {
        guard !Task.isCancelled else { return .unavailable }
        if fadeOut, let player {
            player.setVolume(0, fadeDuration: Self.fade)
            do { try await Task.sleep(for: .seconds(Self.fade)) } catch { return .unavailable }
            guard !Task.isCancelled else { return .unavailable }
        }

        if let player, let loopTrack {
            loopPosition = (loopTrack, player.currentTime)
        }
        player?.stop()
        player = nil
        loopTrack = nil
        guard let mode else { return .applied }
        let track: BackgroundTrack
        let volume: Float
        let loops: Int
        switch mode {
        case let .loop(selection):
            track = selection
            volume = 0.33
            loops = -1
        case let .preview(selection):
            track = selection
            volume = 0.65
            loops = 0
        }
        guard let url = track.recording, let newPlayer = try? AVAudioPlayer(contentsOf: url) else { return .unavailable }
        let session = AVAudioSession.sharedInstance()
        if session.category != .ambient {
            do {
                try session.setCategory(.ambient)
            } catch {
                return .unavailable
            }
        }
        newPlayer.numberOfLoops = loops
        if case .loop = mode, let loopPosition,
           loopPosition.track == track, loopPosition.time < newPlayer.duration {
            newPlayer.currentTime = loopPosition.time
        }
        newPlayer.volume = 0
        guard !Task.isCancelled else { return .unavailable }
        guard newPlayer.play() else { return .activationRejected }
        guard !Task.isCancelled else {
            newPlayer.stop()
            return .unavailable
        }
        newPlayer.setVolume(volume, fadeDuration: Self.fade)
        player = newPlayer
        if case .loop = mode {
            loopTrack = track
            loopPosition = nil
        }
        return .applied
    }
}

struct BackgroundMusicButton: View {
    @Environment(BackgroundMusic.self) private var music
    @AppStorage(BackgroundTrack.storageKey) private var track = BackgroundTrack.off

    var body: some View {
        if track != .off {
            let paused = music.isLoopPaused
            Button(action: music.toggleLoopPause) {
                Label {
                    Text(paused ? "继续播放音乐" : "暂停音乐")
                } icon: {
                    HStack(spacing: 3) {
                        Image(systemName: "music.note")
                        Image(systemName: paused ? "play.fill" : "pause.fill")
                            .font(.caption2)
                    }
                }
                .labelStyle(.iconOnly)
            }
            .accessibilityIdentifier("background-music-toggle")
        }
    }
}
