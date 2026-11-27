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
}
