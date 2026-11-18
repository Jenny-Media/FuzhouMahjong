import StoreKitTest
import XCTest

@MainActor
final class PurchaseFlowTests: XCTestCase {
    func testFreeAllowanceHostOfferTrialAndLifetimeInPortrait() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        // Foundation's argument domain supplies a fresh UI fixture on each launch.
        // Native integration tests separately cover saving and relaunching the archive.
        app.launchArguments += ["-play-access.archive.v1", ""]
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        addUIInterruptionMonitor(withDescription: "Local network access") { alert in
            for name in ["允许", "Allow", "好", "OK"] where alert.buttons[name].exists {
                alert.buttons[name].tap(); return true
            }
            return false
        }
        app.launch()
        let store = try configureStore()
        app.terminate(); app.launch()
        defer { store.clearTransactions() }
        XCTAssertTrue(app.buttons["practice-entry"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["solo-remaining"].label.contains("2"))
        app.buttons["nearby-entry"].tap()
        let host = app.buttons["host-create"]
        reveal(host, in: app); host.tap()
        let buy = app.buttons["lifetime-buy"]
        reveal(buy, in: app)
        XCTAssertTrue(buy.waitForExistence(timeout: 8))
        let priceLoaded = expectation(for: NSPredicate(format: "label CONTAINS %@", "4.99"), evaluatedWith: buy)
        let priceResult = XCTWaiter.wait(for: [priceLoaded], timeout: 10)
        XCTAssertEqual(priceResult, .completed)
        capture("purchase-portrait")
        app.buttons["完成"].tap()
        app.buttons["BackButton"].tap()
        XCUIDevice.shared.orientation = .portrait
        app.buttons["practice-entry"].tap()
        skipOpening(app)
        app.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["solo-remaining"].label.contains("1"))
        app.buttons["practice-entry"].tap()
        app.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["solo-remaining"].label.contains("1"), "Resuming does not charge another hand")
        app.buttons["home-more"].tap(); app.buttons["new-solo-game"].tap()
        skipOpening(app)
        app.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["solo-remaining"].label.contains("0"))
        app.buttons["home-more"].tap(); app.buttons["new-solo-game"].tap()
        XCTAssertTrue(app.staticTexts["access-status"].waitForExistence(timeout: 5))
        let trial = app.buttons["trial-start"]
        reveal(trial, in: app); trial.tap()
        let status = app.staticTexts["access-status"]
        let trialActivated = expectation(for: NSPredicate(format: "label CONTAINS %@", "体验中"), evaluatedWith: status)
        let trialResult = XCTWaiter.wait(for: [trialActivated], timeout: 10)
        XCTAssertEqual(trialResult, .completed)
        reveal(buy, in: app); buy.tap()
        XCTAssertTrue(app.descendants(matching: .any)["lifetime-owned"].waitForExistence(timeout: 10))
        capture("purchase-lifetime-owned")
        XCTAssertFalse(app.buttons["lifetime-buy"].exists)
        XCUIDevice.shared.orientation = .portrait
    }
    func testLandscapePurchaseControlsRemainReachable() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments += ["-play-access.archive.v1", ""]
        app.launch()
        let store = try configureStore()
        app.terminate(); app.launch()
        defer { store.clearTransactions() }
        XCTAssertTrue(app.buttons["solo-remaining"].waitForExistence(timeout: 8))
        app.buttons["solo-remaining"].tap()
        let buy = app.buttons["lifetime-buy"]
        XCTAssertTrue(buy.waitForExistence(timeout: 8))
        reveal(buy, in: app)
        XCTAssertTrue(buy.label.contains("4.99"))
        capture("purchase-landscape")
        reveal(app.buttons["purchase-restore"], in: app)
        // Wide adaptive sheets may minimize their navigation bar while scrolling.
        for _ in 0..<5 where !app.buttons["完成"].isHittable {
            app.scrollViews["purchase-scroll"].swipeDown()
        }
        XCTAssertTrue(app.buttons["完成"].isHittable)
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["solo-remaining"].waitForExistence(timeout: 5))
    }
    private func configureStore() throws -> SKTestSession {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "FuzhouMahjong", withExtension: "storekit"))
        let store = try SKTestSession(contentsOf: file)
        store.resetToDefaultState(); store.clearTransactions(); store.disableDialogs = true
        return store
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<7 where !element.isHittable {
            let scroll = app.scrollViews["purchase-scroll"]
            if scroll.exists { scroll.swipeUp() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }
    private func skipOpening(_ app: XCUIApplication) {
        let skip = app.buttons["skip-opening"]
        if skip.waitForExistence(timeout: 3) { skip.tap() }
        XCTAssertTrue(app.buttons["BackButton"].waitForExistence(timeout: 8))
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
