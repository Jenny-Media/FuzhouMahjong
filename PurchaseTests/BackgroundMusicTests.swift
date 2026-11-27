import AVFoundation
import XCTest
@testable import FuzhouMahjong

@MainActor
final class BackgroundMusicTests: XCTestCase {
    func testBundledTracksArePlayableAndOffHasNoRecording() throws {
        XCTAssertNil(BackgroundTrack.off.recording)
        for track in BackgroundTrack.allCases where track != .off {
            let recording = try XCTUnwrap(track.recording, track.title)
            let player = try AVAudioPlayer(contentsOf: recording)
            XCTAssertTrue((90...120).contains(player.duration), track.title)
        }
    }

    func testMusicOnlyLoopsInPracticeAndSoloAndPreviewsExplicitly() async {
        let music = BackgroundMusic()
        var context = BackgroundMusic.Context(track: .teaHouse, isSolo: false, isActive: true)
        music.update(context)
        defer { music.update(.init()) }
        XCTAssertNil(music.playback)

        music.togglePreview(.teaHouse)
        await expectPlayback(.preview(.teaHouse), in: music)
        music.endPreview()
        XCTAssertNil(music.playback)

        music.setPracticing(true)
        await expectPlayback(.loop(.teaHouse), in: music)
        music.setPracticing(false)
        XCTAssertNil(music.playback)

        context.isSolo = true
        music.update(context)
        await expectPlayback(.loop(.teaHouse), in: music)
        context.track = .tablePulse
        music.update(context)
        await expectPlayback(.loop(.tablePulse), in: music)
        music.togglePreview(.tablePulse)
        await expectPlayback(.preview(.tablePulse), in: music)
        music.endPreview()
        await expectPlayback(.loop(.tablePulse), in: music)

        context.isActive = false
        music.update(context)
        XCTAssertNil(music.playback)
        context.isActive = true
        music.update(context)
        await expectPlayback(.loop(.tablePulse), in: music)
        context.track = .off
        music.update(context)
        XCTAssertNil(music.playback)
    }

    func testInterruptionEndsPreviewAndRestartsSoloMusic() async {
        let music = BackgroundMusic()
        let context = BackgroundMusic.Context(track: .teaHouse, isSolo: true, isActive: true)
        defer { music.update(.init()) }
        music.update(context)
        await expectPlayback(.loop(.teaHouse), in: music)
        music.togglePreview(.teaHouse)
        await expectPlayback(.preview(.teaHouse), in: music)

        music.handleAudioSessionNotification(interruption(.began))
        XCTAssertFalse(music.isPreviewing)
        XCTAssertNil(music.playback)

        music.handleAudioSessionNotification(interruption(.ended))
        await expectPlayback(.loop(.teaHouse), in: music)
    }

    func testPreviewCanRetryAfterAnInterruptionWithoutAnEndEvent() async {
        let music = BackgroundMusic()
        defer { music.update(.init()) }
        music.update(.init(track: .teaHouse, isSolo: true, isActive: true))
        await expectPlayback(.loop(.teaHouse), in: music)

        music.handleAudioSessionNotification(interruption(.began))
        XCTAssertNil(music.playback)
        music.togglePreview(.teaHouse)
        await expectPlayback(.preview(.teaHouse), in: music)
        music.endPreview()
        await expectPlayback(.loop(.teaHouse), in: music)
    }

    func testSystemInterruptionKeepsMusicPausedAcrossForegroundChanges() async throws {
        let music = BackgroundMusic()
        var solo = BackgroundMusic.Context(track: .teaHouse, isSolo: true, isActive: true)
        defer { music.update(.init()) }
        music.update(solo)
        await expectPlayback(.loop(.teaHouse), in: music)

        music.systemInterruptionBegan()
        solo.isActive = false
        music.update(solo)
        music.handleSystemResumption(shouldResume: false)
        solo.isActive = true
        music.update(solo)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(music.playback)

        solo.isActive = false
        music.update(solo)
        music.handleSystemResumption(shouldResume: true)
        XCTAssertNil(music.playback)
        solo.isActive = true
        music.update(solo)
        await expectPlayback(.loop(.teaHouse), in: music)
    }

    func testExplicitPreviewCanRetryWhileWaitingForSystemResumption() async {
        let music = BackgroundMusic()
        defer { music.update(.init()) }
        music.update(.init(track: .teaHouse, isSolo: true, isActive: true))
        await expectPlayback(.loop(.teaHouse), in: music)

        music.systemInterruptionBegan()
        XCTAssertNil(music.playback)
        music.togglePreview(.teaHouse)
        await expectPlayback(.preview(.teaHouse), in: music)
    }

    func testNegativeResumptionWithoutDeactivationPreventsAutomaticPlayback() async throws {
        let music = BackgroundMusic()
        var solo = BackgroundMusic.Context(track: .teaHouse, isSolo: true, isActive: false)
        defer { music.update(.init()) }
        music.update(solo)

        music.handleSystemResumption(shouldResume: false)
        solo.isActive = true
        music.update(solo)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(music.playback)

        music.togglePreview(.teaHouse)
        await expectPlayback(.preview(.teaHouse), in: music)
    }

    func testEarlyResumeRecommendationRetriesAfterAnActivationRejection() async {
        let player = GatedMusicPlayer(rejectingAttempt: 1)
        let music = BackgroundMusic(player: player)
        defer { music.update(.init()) }
        music.update(.init(track: .teaHouse, isSolo: true, isActive: true))
        await expectPendingRejection(in: player)

        music.handleSystemResumption(shouldResume: true)
        await player.finishRejection()
        await expectPlayback(.loop(.teaHouse), in: music)

        let attempts = await player.attempts
        XCTAssertEqual(attempts, [.loop(.teaHouse), .loop(.teaHouse)])
    }

    func testRejectedPreviewKeepsSoloMusicPausedUntilResume() async throws {
        let player = GatedMusicPlayer(rejectingAttempt: 2)
        let music = BackgroundMusic(player: player)
        var solo = BackgroundMusic.Context(track: .teaHouse, isSolo: true, isActive: true)
        defer { music.update(.init()) }
        music.update(solo)
        await expectPlayback(.loop(.teaHouse), in: music)
        music.systemInterruptionBegan()
        music.togglePreview(.teaHouse)
        await expectPendingRejection(in: player)
        await player.finishRejection()

        for _ in 0..<50 where music.isPreviewing {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(music.isPreviewing)
        solo.isActive = false
        music.update(solo)
        solo.isActive = true
        music.update(solo)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(music.playback)
        let attemptsBeforeResume = await player.attempts
        XCTAssertEqual(attemptsBeforeResume, [.loop(.teaHouse), .preview(.teaHouse)])

        music.handleSystemResumption(shouldResume: true)
        await expectPlayback(.loop(.teaHouse), in: music)
    }

    func testStoppingPendingPreviewPreservesSoloMusicPause() async throws {
        let player = GatedMusicPlayer(rejectingAttempt: 2)
        let music = BackgroundMusic(player: player)
        defer { music.update(.init()) }
        music.update(.init(track: .teaHouse, isSolo: true, isActive: true))
        await expectPlayback(.loop(.teaHouse), in: music)
        music.systemInterruptionBegan()
        music.togglePreview(.teaHouse)
        await expectPendingRejection(in: player)

        music.togglePreview(.teaHouse)
        await player.finishRejection()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(music.isPreviewing)
        XCTAssertNil(music.playback)
        let attempts = await player.attempts
        XCTAssertEqual(attempts, [.loop(.teaHouse), .preview(.teaHouse)])

        music.handleSystemResumption(shouldResume: true)
        await expectPlayback(.loop(.teaHouse), in: music)
    }

    func testLeavingDuringPendingPreviewPreservesOutputLossPause() async throws {
        let player = GatedMusicPlayer(rejectingAttempt: 2)
        let music = BackgroundMusic(player: player)
        var solo = BackgroundMusic.Context(track: .teaHouse, isSolo: true, isActive: true)
        defer { music.update(.init()) }
        music.update(solo)
        await expectPlayback(.loop(.teaHouse), in: music)
        music.handleAudioSessionNotification(routeChange(.oldDeviceUnavailable))
        music.togglePreview(.teaHouse)
        await expectPendingRejection(in: player)

        solo.isActive = false
        music.update(solo)
        solo.isActive = true
        music.update(solo)
        await player.finishRejection()
        music.handleSystemResumption(shouldResume: true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(music.isPreviewing)
        XCTAssertNil(music.playback)
        let attempts = await player.attempts
        XCTAssertEqual(attempts, [.loop(.teaHouse), .preview(.teaHouse)])
    }

    func testPreviewFadesBeforeReturningToSoloMusic() async {
        let music = BackgroundMusic()
        defer { music.update(.init()) }
        music.update(.init(track: .teaHouse, isSolo: true, isActive: true))
        await expectPlayback(.loop(.teaHouse), in: music)
        music.togglePreview(.teaHouse)
        await expectPlayback(.preview(.teaHouse), in: music)

        let clock = ContinuousClock()
        let stoppedAt = clock.now
        music.endPreview()
        await expectPlayback(.loop(.teaHouse), in: music)

        XCTAssertGreaterThanOrEqual(stoppedAt.duration(to: clock.now), .milliseconds(220))
    }

    func testOutputDisconnectStopsMusicUntilTheNextExplicitPreview() async throws {
        let music = BackgroundMusic()
        var solo = BackgroundMusic.Context(track: .teaHouse, isSolo: true, isActive: true)
        defer { music.update(.init()) }
        music.update(solo)
        await expectPlayback(.loop(.teaHouse), in: music)

        music.handleAudioSessionNotification(routeChange(.newDeviceAvailable))
        XCTAssertEqual(music.playback, .loop(.teaHouse))
        music.handleAudioSessionNotification(routeChange(.oldDeviceUnavailable))
        XCTAssertNil(music.playback)
        music.systemInterruptionBegan()
        music.handleSystemResumption(shouldResume: true)

        solo.isActive = false
        music.update(solo)
        solo.isActive = true
        music.update(solo)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(music.playback)

        music.togglePreview(.teaHouse)
        await expectPlayback(.preview(.teaHouse), in: music)
        music.endPreview()
        await expectPlayback(.loop(.teaHouse), in: music)
    }

    func testMediaServicesResetClearsPreviewAndWaitsForNewRequest() async throws {
        let music = BackgroundMusic()
        defer { music.update(.init()) }
        music.update(.init(track: .teaHouse, isSolo: true, isActive: true))
        music.togglePreview(.teaHouse)
        await expectPlayback(.preview(.teaHouse), in: music)

        music.handleAudioSessionNotification(Notification(name: AVAudioSession.mediaServicesWereResetNotification))
        XCTAssertFalse(music.isPreviewing)
        XCTAssertNil(music.playback)
        music.handleAudioSessionNotification(interruption(.ended))
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(music.playback)

        music.togglePreview(.teaHouse)
        await expectPlayback(.preview(.teaHouse), in: music)
    }

    private func routeChange(_ reason: AVAudioSession.RouteChangeReason) -> Notification {
        Notification(name: AVAudioSession.routeChangeNotification, userInfo: [
            AVAudioSessionRouteChangeReasonKey: reason.rawValue,
        ])
    }

    private func interruption(_ type: AVAudioSession.InterruptionType) -> Notification {
        Notification(name: AVAudioSession.interruptionNotification, userInfo: [
            AVAudioSessionInterruptionTypeKey: type.rawValue,
        ])
    }

    private func expectPlayback(_ expected: BackgroundMusic.Playback, in music: BackgroundMusic,
                                file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<50 {
            if music.playback == expected { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(music.playback, expected, file: file, line: line)
    }

    private func expectPendingRejection(in player: GatedMusicPlayer,
                                        file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<50 {
            if await player.isRejecting { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Expected a pending activation rejection", file: file, line: line)
    }
}

private actor GatedMusicPlayer: BackgroundMusicPlaying {
    private let rejectingAttempt: Int
    private var rejection: CheckedContinuation<Void, Never>?
    private(set) var attempts: [BackgroundMusic.Playback] = []

    var isRejecting: Bool { rejection != nil }

    init(rejectingAttempt: Int) {
        self.rejectingAttempt = rejectingAttempt
    }

    func apply(_ mode: BackgroundMusic.Playback?, fadeOut: Bool) async -> BackgroundMusic.PlaybackResult {
        guard let mode else { return .applied }
        attempts.append(mode)
        guard attempts.count == rejectingAttempt else { return .applied }
        await withCheckedContinuation { rejection = $0 }
        return .activationRejected
    }

    func finishRejection() {
        rejection?.resume()
        rejection = nil
    }
}
