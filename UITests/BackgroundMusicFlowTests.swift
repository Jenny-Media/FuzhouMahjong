import XCTest

@MainActor
final class BackgroundMusicFlowTests: XCTestCase {
    func testQuickMusicControlIsSharedBySoloAndPractice() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-play-access.archive.v1", "", "-backgroundMusic.track", "tea-house",
                               "-backgroundMusic.paused", "NO", "--ui-test-manual-opening"]
        app.launch()

        let solo = app.buttons["practice-entry"]
        XCTAssertTrue(solo.waitForExistence(timeout: 8))
        solo.tap()
        let start = app.buttons["start-solo-setup"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        let skip = app.buttons["skip-opening"]
        if skip.waitForExistence(timeout: 3) { skip.tap() }
        let music = app.buttons["background-music-toggle"]
        XCTAssertTrue(music.waitForExistence(timeout: 5))
        XCTAssertTrue(music.isHittable)
        XCTAssertEqual(music.label, "暂停音乐")
        let tableCapture = XCTAttachment(screenshot: app.screenshot())
        tableCapture.name = "table-music-control"
        tableCapture.lifetime = .keepAlways
        add(tableCapture)
        music.tap()
        XCTAssertEqual(music.label, "继续播放音乐")

        let settings = app.buttons["table-settings"]
        if settings.exists {
            settings.tap()
        } else {
            let overflow = app.buttons["TopOverflowBarButtonItem"]
            XCTAssertTrue(overflow.isHittable)
            overflow.tap()
            app.buttons["设置"].tap()
        }
        let preview = app.buttons["background-music-preview"]
        reveal(preview, in: app)
        preview.tap()
        XCTAssertEqual(preview.label, "停止试听")
        let done = app.navigationBars["设置"].buttons["完成"]
        for _ in 0..<4 where !done.isHittable {
            app.collectionViews.firstMatch.swipeDown()
        }
        XCTAssertTrue(done.isHittable)
        done.tap()
        XCTAssertTrue(music.waitForExistence(timeout: 5))
        XCTAssertEqual(music.label, "继续播放音乐")

        app.buttons["BackButton"].tap()
        let practice = app.buttons["home-gesture-practice"]
        XCTAssertTrue(practice.waitForExistence(timeout: 5))
        practice.tap()
        XCTAssertTrue(music.waitForExistence(timeout: 5))
        XCTAssertEqual(music.label, "继续播放音乐")
        app.buttons["gesture-practice-lesson-multipleChows"].tap()
        XCTAssertTrue(music.isHittable)
        music.tap()
        XCTAssertEqual(music.label, "暂停音乐")
        app.buttons["gesture-practice-close"].tap()
        XCTAssertTrue(app.buttons["gesture-practice-picker-close"].waitForExistence(timeout: 5))
        XCTAssertEqual(music.label, "暂停音乐")
    }

    func testSettingsPreviewAndTrackPersistAcrossLaunches() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        let picker = openMusicSettings(in: app)
        let preview = app.buttons["background-music-preview"]
        picker.tap()
        app.buttons["关闭"].tap()
        XCTAssertFalse(preview.exists)

        picker.tap()
        app.buttons["榕城夜色"].tap()
        reveal(preview, in: app)
        XCTAssertEqual(preview.label, "试听")
        preview.tap()
        XCTAssertEqual(preview.label, "停止试听")
        preview.tap()
        XCTAssertEqual(preview.label, "试听")

        app.terminate()
        app.launch()
        let savedPicker = openMusicSettings(in: app)
        let savedSelection = savedPicker.label + " " + ((savedPicker.value as? String) ?? "")
        XCTAssertTrue(savedSelection.contains("榕城夜色"), savedSelection)
        savedPicker.tap()
        app.buttons["关闭"].tap()
        XCTAssertFalse(preview.exists)
    }

    private func openMusicSettings(in app: XCUIApplication) -> XCUIElement {
        let more = app.buttons["home-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 8))
        more.tap()
        app.buttons["设置"].tap()
        let picker = app.buttons["background-music-track"]
        reveal(picker, in: app)
        return picker
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let settings = app.collectionViews.firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        for _ in 0..<6 {
            if element.isHittable { break }
            settings.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
}
