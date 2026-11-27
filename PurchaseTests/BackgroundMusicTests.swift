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

        music.handleAudioSessionNotification(interruption(.ended, options: .shouldResume))
        await expectPlayback(.loop(.teaHouse), in: music)
    }

    func testClosingSettingsWaitsForLegacyInterruptionResumePermission() async throws {
        let player = GatedMusicPlayer(gatedAttempt: .max)
        let music = BackgroundMusic(player: player)
        defer { music.update(.init()) }
        music.update(.init(track: .teaHouse, isSolo: true, isActive: true))
        await expectPlayback(.loop(.teaHouse), in: music)

        music.setSettingsPresented(true)
        music.handleAudioSessionNotification(interruption(.began))
        music.setSettingsPresented(false)
        XCTAssertTrue(music.isLoopPaused)
        XCTAssertNil(music.playback)
        music.handleAudioSessionNotification(interruption(.ended))
        try await Task.sleep(for: .milliseconds(100))
        let attempts = await player.attempts
        XCTAssertEqual(attempts, [.loop(.teaHouse)])
        XCTAssertTrue(music.isLoopPaused)
        XCTAssertNil(music.playback)

        music.toggleLoopPause()
        await expectPlayback(.loop(.teaHouse), in: music)
    }

    func testQuickResumeWorksWhenLegacyInterruptionEndIsMissing() async {
        let music = BackgroundMusic(player: GatedMusicPlayer(gatedAttempt: .max))
        defer { music.update(.init()) }
        music.update(.init(track: .teaHouse, isSolo: true, isActive: true))
        await expectPlayback(.loop(.teaHouse), in: music)

        music.handleAudioSessionNotification(interruption(.began))
        XCTAssertTrue(music.isLoopPaused)
        XCTAssertNil(music.playback)
        music.toggleLoopPause()
        await expectPlayback(.loop(.teaHouse), in: music)
        XCTAssertFalse(music.isLoopPaused)
    }

    func testLateNegativeResumptionDoesNotCancelExplicitPlayback() async {
        for expected: BackgroundMusic.Playback in [.loop(.teaHouse), .preview(.teaHouse)] {
            let player = GatedMusicPlayer(gatedAttempt: 2, outcome: .applied)
            let music = BackgroundMusic(player: player)
            defer { music.update(.init()) }
            music.update(.init(track: .teaHouse, isSolo: true, isActive: true))
            await expectPlayback(.loop(.teaHouse), in: music)
            music.handleAudioSessionNotification(interruption(.began))

            switch expected {
            case .loop: music.toggleLoopPause()
            case .preview: music.togglePreview(.teaHouse)
            }
            await expectPendingActivation(in: player)
            music.handleAudioSessionNotification(interruption(.ended))
            await player.finishActivation()

            await expectPlayback(expected, in: music)
        }
    }

    func testCanceledExplicitPlaybackRetainsNegativeResumptionHold() async throws {
        for attempt: BackgroundMusic.Playback in [.preview(.teaHouse), .loop(.teaHouse)] {
            let player = GatedMusicPlayer(gatedAttempt: 2, outcome: .applied)
            let music = BackgroundMusic(player: player)
            defer { music.update(.init()) }
            music.update(.init(track: .teaHouse, isSolo: true, isActive: true))
            await expectPlayback(.loop(.teaHouse), in: music)

            switch attempt {
            case .preview:
                music.setSettingsPresented(true)
                music.togglePreview(.teaHouse)
            case .loop:
                music.systemInterruptionBegan()
                music.toggleLoopPause()
            }
            await expectPendingActivation(in: player)
            if case .loop = attempt { music.handleSystemResumption(shouldResume: true) }
            music.handleSystemResumption(shouldResume: false)
            XCTAssertTrue(music.isLoopPaused)

            if case .loop = attempt { music.setSettingsPresented(true) }
            music.setSettingsPresented(false)
            await player.finishActivation()
            try await Task.sleep(for: .milliseconds(100))
            let attempts = await player.attempts
            XCTAssertEqual(attempts, [.loop(.teaHouse), attempt])
            XCTAssertNil(music.playback)
            XCTAssertTrue(music.isLoopPaused)

            music.toggleLoopPause()
            await expectPlayback(.loop(.teaHouse), in: music)
            XCTAssertFalse(music.isLoopPaused)
        }
    }

    func testAuditionRetainsNegativeResumptionHoldAfterSettingsCloses() async {
        for auditionPending in [true, false] {
            let player = GatedMusicPlayer(gatedAttempt: 2, outcome: .applied)
            let music = BackgroundMusic(player: player)
            defer { music.update(.init()) }
            music.update(.init(track: .teaHouse, isSolo: true, isActive: true))
            await expectPlayback(.loop(.teaHouse), in: music)

            music.setSettingsPresented(true)
            music.handleAudioSessionNotification(interruption(.began))
            music.togglePreview(.teaHouse)
            await expectPendingActivation(in: player)
            if auditionPending { music.handleAudioSessionNotification(interruption(.ended)) }
            await player.finishActivation()
            await expectPlayback(.preview(.teaHouse), in: music)
            if !auditionPending { music.handleAudioSessionNotification(interruption(.ended)) }

            XCTAssertEqual(music.playback, .preview(.teaHouse))
            music.setSettingsPresented(false)
            XCTAssertTrue(music.isLoopPaused, "Audition pending when interruption ended: \(auditionPending)")
            XCTAssertNil(music.playback)

            music.handleAudioSessionNotification(interruption(.ended, options: .shouldResume))
            await expectPlayback(.loop(.teaHouse), in: music)
        }
    }

    func testNegativeResumptionCancelsPendingAutomaticPlayback() async {
        let player = GatedMusicPlayer(gatedAttempt: 1, outcome: .applied)
        let music = BackgroundMusic(player: player)
        defer { music.update(.init()) }
        music.update(.init(track: .teaHouse, isSolo: true, isActive: true))
        await expectPendingActivation(in: player)

        music.handleSystemResumption(shouldResume: false)
        await player.finishActivation()
        XCTAssertTrue(music.isLoopPaused)
        XCTAssertNil(music.playback)
    }

    func testLateNegativeResumptionClearsAnEarlierRecommendationToRetry() async throws {
        let player = GatedMusicPlayer(gatedAttempt: 2)
        let music = BackgroundMusic(player: player)
        defer { music.update(.init()) }
        music.update(.init(track: .teaHouse, isSolo: true, isActive: true))
        await expectPlayback(.loop(.teaHouse), in: music)
        music.systemInterruptionBegan()
        music.toggleLoopPause()
        await expectPendingActivation(in: player)

        music.handleSystemResumption(shouldResume: true)
        music.handleSystemResumption(shouldResume: false)
        await player.finishActivation()
        try await Task.sleep(for: .milliseconds(100))
        let attempts = await player.attempts
        XCTAssertEqual(attempts, [.loop(.teaHouse), .loop(.teaHouse)])
        XCTAssertTrue(music.isLoopPaused)
        XCTAssertNil(music.playback)
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
        let player = GatedMusicPlayer(gatedAttempt: 1)
        let music = BackgroundMusic(player: player)
        defer { music.update(.init()) }
        music.update(.init(track: .teaHouse, isSolo: true, isActive: true))
        await expectPendingActivation(in: player)

        music.handleSystemResumption(shouldResume: true)
        await player.finishActivation()
        await expectPlayback(.loop(.teaHouse), in: music)

        let attempts = await player.attempts
        XCTAssertEqual(attempts, [.loop(.teaHouse), .loop(.teaHouse)])
    }

    func testRejectedPreviewKeepsSoloMusicPausedUntilResume() async throws {
        let player = GatedMusicPlayer(gatedAttempt: 2)
        let music = BackgroundMusic(player: player)
        var solo = BackgroundMusic.Context(track: .teaHouse, isSolo: true, isActive: true)
        defer { music.update(.init()) }
        music.update(solo)
        await expectPlayback(.loop(.teaHouse), in: music)
        music.systemInterruptionBegan()
        music.togglePreview(.teaHouse)
        await expectPendingActivation(in: player)
        await player.finishActivation()

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
        let player = GatedMusicPlayer(gatedAttempt: 2)
        let music = BackgroundMusic(player: player)
        defer { music.update(.init()) }
        music.update(.init(track: .teaHouse, isSolo: true, isActive: true))
        await expectPlayback(.loop(.teaHouse), in: music)
        music.systemInterruptionBegan()
        music.togglePreview(.teaHouse)
        await expectPendingActivation(in: player)

        music.togglePreview(.teaHouse)
        await player.finishActivation()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(music.isPreviewing)
        XCTAssertNil(music.playback)
        let attempts = await player.attempts
        XCTAssertEqual(attempts, [.loop(.teaHouse), .preview(.teaHouse)])

        music.handleSystemResumption(shouldResume: true)
        await expectPlayback(.loop(.teaHouse), in: music)
    }

    func testLeavingDuringPendingPreviewPreservesOutputLossPause() async throws {
        let player = GatedMusicPlayer(gatedAttempt: 2)
        let music = BackgroundMusic(player: player)
        var solo = BackgroundMusic.Context(track: .teaHouse, isSolo: true, isActive: true)
        defer { music.update(.init()) }
        music.update(solo)
        await expectPlayback(.loop(.teaHouse), in: music)
        music.handleAudioSessionNotification(routeChange(.oldDeviceUnavailable))
        music.togglePreview(.teaHouse)
        await expectPendingActivation(in: player)

        solo.isActive = false
        music.update(solo)
        solo.isActive = true
        music.update(solo)
        await player.finishActivation()
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
        music.setSettingsPresented(true)
        music.togglePreview(.teaHouse)
        await expectPlayback(.preview(.teaHouse), in: music)

        let clock = ContinuousClock()
        let stoppedAt = clock.now
        music.setSettingsPresented(false)
        await expectPlayback(.loop(.teaHouse), in: music)

        XCTAssertGreaterThanOrEqual(stoppedAt.duration(to: clock.now), .milliseconds(220))
    }

    func testSettingsStaysQuietAfterASelectionChangeAndAfterStoppingPreview() async throws {
        let player = GatedMusicPlayer(gatedAttempt: .max)
        let music = BackgroundMusic(player: player)
        var solo = BackgroundMusic.Context(track: .teaHouse, isSolo: true, isActive: true)
        defer { music.update(.init()) }
        music.update(solo)
        await expectPlayback(.loop(.teaHouse), in: music)

        music.setSettingsPresented(true)
        XCTAssertNil(music.playback)
        solo.track = .tablePulse
        music.update(solo)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(music.playback)
        let attemptsBeforePreview = await player.attempts
        XCTAssertEqual(attemptsBeforePreview, [.loop(.teaHouse)])

        music.togglePreview(.tablePulse)
        await expectPlayback(.preview(.tablePulse), in: music)
        music.endPreview()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(music.playback)
        let attemptsAfterPreview = await player.attempts
        XCTAssertEqual(attemptsAfterPreview, [.loop(.teaHouse), .preview(.tablePulse)])

        music.setSettingsPresented(false)
        await expectPlayback(.loop(.tablePulse), in: music)
    }

    func testPlayerPauseSurvivesSettingsAndRelaunch() async throws {
        let suite = "BackgroundMusicTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let music = BackgroundMusic(player: GatedMusicPlayer(gatedAttempt: .max), defaults: defaults)
        let solo = BackgroundMusic.Context(track: .teaHouse, isSolo: true, isActive: true)
        music.update(solo)
        await expectPlayback(.loop(.teaHouse), in: music)

        music.toggleLoopPause()
        XCTAssertTrue(music.isLoopPaused)
        XCTAssertNil(music.playback)
        music.setSettingsPresented(true)
        music.togglePreview(.teaHouse)
        await expectPlayback(.preview(.teaHouse), in: music)
        music.setSettingsPresented(false)
        XCTAssertFalse(music.isPreviewing)
        XCTAssertTrue(music.isLoopPaused)
        XCTAssertNil(music.playback)
        music.update(.init())

        let player = GatedMusicPlayer(gatedAttempt: .max)
        let reopened = BackgroundMusic(player: player, defaults: defaults)
        defer { reopened.update(.init()) }
        reopened.update(.init(track: .teaHouse, isActive: true))
        reopened.setPracticing(true)
        XCTAssertTrue(reopened.isLoopPaused)
        XCTAssertNil(reopened.playback)
        reopened.toggleLoopPause()
        await expectPlayback(.loop(.teaHouse), in: reopened)
        let attempts = await player.attempts
        XCTAssertEqual(attempts, [.loop(.teaHouse)])
        XCTAssertFalse(defaults.bool(forKey: BackgroundMusic.pauseStorageKey))
    }

    func testOutputDisconnectOnHomeDoesNotPauseNextLoop() async {
        for startsPractice in [false, true] {
            let music = BackgroundMusic(player: GatedMusicPlayer(gatedAttempt: .max))
            defer { music.update(.init()) }
            music.update(.init(track: .teaHouse, isActive: true))

            music.handleAudioSessionNotification(routeChange(.oldDeviceUnavailable))
            XCTAssertFalse(music.isLoopPaused)

            if startsPractice {
                music.setPracticing(true)
            } else {
                music.update(.init(track: .teaHouse, isSolo: true, isActive: true))
            }
            await expectPlayback(.loop(.teaHouse), in: music)
        }
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
        music.handleAudioSessionNotification(interruption(.ended, options: .shouldResume))
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(music.playback)

        music.togglePreview(.teaHouse)
        await expectPlayback(.preview(.teaHouse), in: music)
    }

    func testTrackChangeAndNavigationPreserveOutputDisconnectPause() async throws {
        let player = GatedMusicPlayer(gatedAttempt: .max)
        let music = BackgroundMusic(player: player)
        defer { music.update(.init()) }
        music.update(.init(track: .teaHouse, isSolo: true, isActive: true))
        await expectPlayback(.loop(.teaHouse), in: music)

        music.setSettingsPresented(true)
        music.handleAudioSessionNotification(routeChange(.oldDeviceUnavailable))
        music.update(.init(track: .tablePulse, isSolo: true, isActive: true))
        music.setSettingsPresented(false)
        XCTAssertTrue(music.isLoopPaused)
        XCTAssertNil(music.playback)

        music.update(.init(track: .tablePulse, isActive: true))
        music.setPracticing(true)
        XCTAssertTrue(music.isLoopPaused)
        music.setPracticing(false)
        music.update(.init(track: .tablePulse, isSolo: true, isActive: true))
        music.handleSystemResumption(shouldResume: true)
        try await Task.sleep(for: .milliseconds(100))
        let attempts = await player.attempts
        XCTAssertEqual(attempts, [.loop(.teaHouse)])
        XCTAssertTrue(music.isLoopPaused)
        XCTAssertNil(music.playback)

        music.toggleLoopPause()
        await expectPlayback(.loop(.tablePulse), in: music)
    }

    func testCancelingQuickResumeDoesNotReleaseOutputDisconnectPause() async throws {
        let player = GatedMusicPlayer(gatedAttempt: 2, outcome: .applied)
        let music = BackgroundMusic(player: player)
        defer { music.update(.init()) }
        music.update(.init(track: .teaHouse, isSolo: true, isActive: true))
        await expectPlayback(.loop(.teaHouse), in: music)
        music.handleAudioSessionNotification(routeChange(.oldDeviceUnavailable))
        music.toggleLoopPause()
        await expectPendingActivation(in: player)

        music.setSettingsPresented(true)
        await player.finishActivation()
        music.setSettingsPresented(false)
        try await Task.sleep(for: .milliseconds(100))
        let attempts = await player.attempts
        XCTAssertEqual(attempts, [.loop(.teaHouse), .loop(.teaHouse)])
        XCTAssertTrue(music.isLoopPaused)
        XCTAssertNil(music.playback)

        music.toggleLoopPause()
        await expectPlayback(.loop(.teaHouse), in: music)
        XCTAssertFalse(music.isLoopPaused)
    }

    func testRejectedQuickResumeDoesNotReleaseOutputDisconnectPause() async throws {
        let player = GatedMusicPlayer(gatedAttempt: 2)
        let music = BackgroundMusic(player: player)
        defer { music.update(.init()) }
        music.update(.init(track: .teaHouse, isSolo: true, isActive: true))
        await expectPlayback(.loop(.teaHouse), in: music)
        music.handleAudioSessionNotification(routeChange(.oldDeviceUnavailable))
        music.toggleLoopPause()
        await expectPendingActivation(in: player)

        await player.finishActivation()
        try await Task.sleep(for: .milliseconds(100))
        music.handleSystemResumption(shouldResume: true)
        try await Task.sleep(for: .milliseconds(100))
        let attempts = await player.attempts
        XCTAssertEqual(attempts, [.loop(.teaHouse), .loop(.teaHouse)])
        XCTAssertTrue(music.isLoopPaused)
        XCTAssertNil(music.playback)
    }

    func testUnavailableLoopCanRetryWithOneTap() async throws {
        let player = GatedMusicPlayer(gatedAttempt: 1, outcome: .unavailable)
        let music = BackgroundMusic(player: player)
        defer { music.update(.init()) }
        music.update(.init(track: .teaHouse, isSolo: true, isActive: true))
        await expectPendingActivation(in: player)

        await player.finishActivation()
        for _ in 0..<50 where !music.isLoopPaused {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(music.isLoopPaused)
        XCTAssertNil(music.playback)
        music.toggleLoopPause()
        await expectPlayback(.loop(.teaHouse), in: music)
        XCTAssertFalse(music.isLoopPaused)
    }

    func testChangingUnavailableTrackAllowsNewTrackToPlay() async throws {
        let player = GatedMusicPlayer(gatedAttempt: 1, outcome: .unavailable)
        let music = BackgroundMusic(player: player)
        var solo = BackgroundMusic.Context(track: .teaHouse, isSolo: true, isActive: true)
        defer { music.update(.init()) }
        music.update(solo)
        await expectPendingActivation(in: player)

        await player.finishActivation()
        for _ in 0..<50 where !music.isLoopPaused {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(music.isLoopPaused)

        music.setSettingsPresented(true)
        solo.track = .tablePulse
        music.update(solo)
        XCTAssertNil(music.playback)
        music.setSettingsPresented(false)
        await expectPlayback(.loop(.tablePulse), in: music)
        XCTAssertFalse(music.isLoopPaused)
    }

    private func routeChange(_ reason: AVAudioSession.RouteChangeReason) -> Notification {
        Notification(name: AVAudioSession.routeChangeNotification, userInfo: [
            AVAudioSessionRouteChangeReasonKey: reason.rawValue,
        ])
    }

    private func interruption(_ type: AVAudioSession.InterruptionType,
                              options: AVAudioSession.InterruptionOptions? = nil) -> Notification {
        var info = [AVAudioSessionInterruptionTypeKey: type.rawValue]
        if let options { info[AVAudioSessionInterruptionOptionKey] = options.rawValue }
        return Notification(name: AVAudioSession.interruptionNotification, userInfo: info)
    }

    private func expectPlayback(_ expected: BackgroundMusic.Playback, in music: BackgroundMusic,
                                file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<50 {
            if music.playback == expected { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(music.playback, expected, file: file, line: line)
    }

    private func expectPendingActivation(in player: GatedMusicPlayer,
                                        file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<50 {
            if await player.isWaiting { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Expected a pending activation", file: file, line: line)
    }
}

private actor GatedMusicPlayer: BackgroundMusicPlaying {
    private let gatedAttempt: Int
    private let outcome: BackgroundMusic.PlaybackResult
    private var activation: CheckedContinuation<Void, Never>?
    private(set) var attempts: [BackgroundMusic.Playback] = []

    var isWaiting: Bool { activation != nil }

    init(gatedAttempt: Int, outcome: BackgroundMusic.PlaybackResult = .activationRejected) {
        self.gatedAttempt = gatedAttempt
        self.outcome = outcome
    }

    func apply(_ mode: BackgroundMusic.Playback?, fadeOut: Bool) async -> BackgroundMusic.PlaybackResult {
        guard let mode else { return .applied }
        attempts.append(mode)
        guard attempts.count == gatedAttempt else { return .applied }
        await withCheckedContinuation { activation = $0 }
        return outcome
    }

    func finishActivation() {
        activation?.resume()
        activation = nil
    }
}
