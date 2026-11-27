import AVFoundation
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
    struct Context: Equatable {
        var track: BackgroundTrack = .off
        var isSolo = false
        var isActive = false
    }

    enum Playback: Equatable {
        case loop(BackgroundTrack)
        case preview(BackgroundTrack)
    }

    private(set) var playback: Playback?
    @ObservationIgnored private var context = Context()
    @ObservationIgnored private var isPracticing = false
    @ObservationIgnored private var isInterrupted = false
    @ObservationIgnored private var previewTrack: BackgroundTrack?
    @ObservationIgnored private let player = BackgroundMusicPlayer()
    @ObservationIgnored private var requestedPlayback: Playback?
    @ObservationIgnored private var transition: Task<Void, Never>?
    @ObservationIgnored private var previewTimer: Task<Void, Never>?

    var isPreviewing: Bool {
        if case .preview = playback { return true }
        return false
    }

    func update(_ newContext: Context) {
        if newContext.isActive && !context.isActive { isInterrupted = false }
        if newContext.track != context.track && previewTrack != newContext.track { clearPreview() }
        context = newContext
        if !context.isActive {
            clearPreview()
            request(nil, fadeOut: false, force: true)
        } else {
            refresh()
        }
    }

    func setPracticing(_ practicing: Bool) {
        isPracticing = practicing
        refresh()
    }

    func togglePreview(_ track: BackgroundTrack) {
        guard context.isActive, !isInterrupted, track != .off else { return }
        if previewTrack == track {
            endPreview()
            return
        }
        clearPreview()
        previewTrack = track
        refresh()
        previewTimer = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            self?.endPreview()
        }
    }

    func endPreview() {
        guard previewTrack != nil else { return }
        clearPreview()
        refresh()
    }

    func handleInterruption(_ notification: Notification) {
        guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: value) else { return }
        isInterrupted = type == .began
        if isInterrupted {
            clearPreview()
            request(nil, fadeOut: false, force: true)
        } else {
            refresh()
        }
    }

    private func clearPreview() {
        previewTimer?.cancel()
        previewTimer = nil
        previewTrack = nil
    }

    private func refresh() {
        guard context.isActive, !isInterrupted else { return }
        if let previewTrack {
            request(.preview(previewTrack))
        } else if context.track != .off && (context.isSolo || isPracticing) {
            request(.loop(context.track))
        } else {
            request(nil)
        }
    }

    private func request(_ mode: Playback?, fadeOut: Bool = true, force: Bool = false) {
        guard force || requestedPlayback != mode else { return }
        requestedPlayback = mode
        playback = nil
        transition?.cancel()
        transition = Task { [weak self, player] in
            let started = await player.apply(mode, fadeOut: fadeOut)
            guard !Task.isCancelled, let self else { return }
            playback = started
            if started != mode {
                requestedPlayback = nil
                if previewTrack != nil { endPreview() }
            }
        }
    }
}

// Audio session setup and file playback can block. The player owns them off the UI actor.
private actor BackgroundMusicPlayer {
    private static let fade = 0.24
    private var player: AVAudioPlayer?

    func apply(_ mode: BackgroundMusic.Playback?, fadeOut: Bool) async -> BackgroundMusic.Playback? {
        guard !Task.isCancelled else { return nil }
        guard let mode else {
            if fadeOut, let player {
                player.setVolume(0, fadeDuration: Self.fade)
                do { try await Task.sleep(for: .seconds(Self.fade)) } catch { return nil }
                guard !Task.isCancelled else { return nil }
            }
            stop()
            return nil
        }

        stop()
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
        guard let url = track.recording, let newPlayer = try? AVAudioPlayer(contentsOf: url) else { return nil }
        let session = AVAudioSession.sharedInstance()
        if session.category != .ambient { try? session.setCategory(.ambient) }
        newPlayer.numberOfLoops = loops
        newPlayer.volume = 0
        guard !Task.isCancelled, newPlayer.play() else { return nil }
        guard !Task.isCancelled else {
            newPlayer.stop()
            return nil
        }
        newPlayer.setVolume(volume, fadeDuration: Self.fade)
        player = newPlayer
        return mode
    }

    private func stop() {
        player?.stop()
        player = nil
    }
}
