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

    private func expectPlayback(_ expected: BackgroundMusic.Playback, in music: BackgroundMusic,
                                file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<50 {
            if music.playback == expected { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(music.playback, expected, file: file, line: line)
    }
}
