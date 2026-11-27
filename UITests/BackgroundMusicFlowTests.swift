import XCTest

@MainActor
final class BackgroundMusicFlowTests: XCTestCase {
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
