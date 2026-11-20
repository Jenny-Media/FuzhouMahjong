import FuzhouCore
import StoreKitTest
import XCTest

@MainActor
final class PurchaseFlowTests: XCTestCase {
    func testEnteringAnotherInviteCodeCancelsTheCurrentSearch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let invitation = try XCTUnwrap(URL(string: "fuzhou-mahjong://join/\(UUID().uuidString)"))
        app.open(invitation)
        let cancel = app.buttons["cancel-invite-search"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        let code = app.textFields["4 位邀请码"]
        reveal(code, in: app)
        code.tap()
        code.typeText("ABCD")
        XCTAssertEqual(code.value as? String, "ABCD")
        XCTAssertFalse(cancel.exists)
    }

    func testNearbyNicknameCanBeEditedAndSurvivesRelaunch() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        app.buttons["nearby-entry"].tap()
        let nickname = app.buttons["nearby-nickname"]
        XCTAssertTrue(nickname.waitForExistence(timeout: 5))
        let original = try XCTUnwrap(nickname.value as? String)
        XCTAssertFalse(original.isEmpty)
        XCTAssertNotEqual(original, "牌友")
        XCTAssertLessThan(nickname.frame.maxY, app.buttons["scan-invite"].frame.minY)
        capture("nearby-nickname-lobby")

        nickname.tap()
        let field = app.textFields["nearby-nickname-input"]
        let roll = app.buttons["nearby-nickname-random"]
        let save = app.buttons["nearby-nickname-save"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, original)
        roll.tap()
        let suggestion = try XCTUnwrap(field.value as? String)
        XCTAssertNotEqual(suggestion, original)
        XCTAssertEqual(suggestion.count, 2)
        XCTAssertTrue(suggestion.allSatisfy(\.isLetter))
        capture("nearby-nickname-editor")
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let deletions = String(repeating: XCUIKeyboardKey.delete.rawValue, count: suggestion.count)
        field.typeText(deletions + "RiverSeat")
        XCTAssertEqual(field.value as? String, "RiverSeat")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5))
        XCTAssertEqual(nickname.value as? String, "RiverSeat")

        app.terminate()
        app.launch()
        app.buttons["nearby-entry"].tap()
        XCTAssertTrue(nickname.waitForExistence(timeout: 5))
        XCTAssertEqual(nickname.value as? String, "RiverSeat")
    }

    func testGuestsSeeJoiningFirstAndHostingHasItsOwnSetup() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-nearby.nickname", "测试房主", "-nearby.customRulesetID", ""]
        app.launch()
        let store = try configureStore()
        defer { store.clearTransactions() }
        _ = try await store.buyProduct(identifier: "media.jenny.FuzhouMahjong.lifetime")
        app.terminate()
        app.launch()
        app.buttons["nearby-entry"].tap()
        let scan = app.buttons["scan-invite"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        XCTAssertTrue(scan.isHittable)
        XCTAssertTrue(app.textFields["4 位邀请码"].isHittable)
        XCTAssertFalse(app.switches["pure-suit-bonus"].exists)
        capture("guest-first-lobby")
        let create = app.buttons["host-create"]
        reveal(create, in: app)
        create.tap()
        let bonus = app.switches["pure-suit-bonus"]
        XCTAssertTrue(bonus.waitForExistence(timeout: 5))
        let desiredTitle = bonus.value as? String == "1" ? "清一色不加分" : "清一色加分"
        bonus.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        app.buttons["confirm-host-create"].tap()
        let rules = app.descendants(matching: .any).matching(identifier: "room-ruleset").firstMatch
        XCTAssertTrue(rules.waitForExistence(timeout: 5))
        XCTAssertTrue(rules.label.contains(desiredTitle))
        XCTAssertTrue(app.staticTexts["测试房主"].exists)
        app.buttons["离开牌桌"].tap()
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
    }

    func testHostSetupHonorsSavedCustomRules() async throws {
        continueAfterFailure = false
        let preset = FuzhouHouseRules(name: "同桌家规")
        let data = try JSONEncoder().encode([preset]).map { String(format: "%02x", $0) }.joined()
        let app = XCUIApplication()
        app.launchArguments = ["-table.custom-rulesets.v1", "<\(data)>", "-nearby.customRulesetID", preset.id.uuidString]
        app.launch()
        let store = try configureStore()
        defer { store.clearTransactions() }
        _ = try await store.buyProduct(identifier: "media.jenny.FuzhouMahjong.lifetime")
        app.terminate()
        app.launch()
        app.buttons["nearby-entry"].tap()
        let create = app.buttons["host-create"]
        reveal(create, in: app)
        create.tap()
        let menu = app.buttons["custom-rules-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertTrue(menu.label.contains(preset.name))
        XCTAssertFalse(app.switches["pure-suit-bonus"].exists)
        app.buttons["confirm-host-create"].tap()
        let rules = app.descendants(matching: .any).matching(identifier: "room-ruleset").firstMatch
        XCTAssertTrue(rules.waitForExistence(timeout: 5))
        XCTAssertTrue(rules.label.contains(preset.name))
        app.buttons["离开牌桌"].tap()
    }

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
        reveal(host, in: app)
        capture("nearby-lobby")
        host.tap()
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
        startSetup(app)
        skipOpening(app)
        app.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["solo-remaining"].label.contains("1"))
        app.buttons["practice-entry"].tap()
        app.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["solo-remaining"].label.contains("1"), "Resuming does not charge another hand")
        let newGame = app.buttons["new-solo-game"]
        reveal(newGame, in: app)
        newGame.tap()
        startSetup(app)
        let prompt = app.alerts["开始新的单机牌局？"]
        let confirm = prompt.buttons["confirm-new-solo-game"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        prompt.buttons["取消"].firstMatch.tap()
        XCTAssertTrue(prompt.waitForNonExistence(timeout: 5))
        let cancelSetup = app.buttons["cancel-solo-setup"]
        cancelSetup.tap()
        XCTAssertTrue(cancelSetup.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["practice-entry"].label.contains("继续单机"))
        XCTAssertTrue(app.buttons["solo-remaining"].label.contains("1"))
        newGame.tap()
        startSetup(app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        skipOpening(app)
        app.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["solo-remaining"].label.contains("0"))
        reveal(newGame, in: app)
        newGame.tap()
        startSetup(app)
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
        XCTAssertTrue(app.buttons["完成"].isHittable)
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["solo-remaining"].waitForExistence(timeout: 5))
    }

    func testTableControlsRemainReachableAfterRotation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-play-access.archive.v1", ""]
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()

        let play = app.buttons["practice-entry"]
        XCTAssertTrue(play.waitForExistence(timeout: 8))
        capture("home-portrait")
        play.tap()
        startSetup(app)
        skipOpening(app)

        let gold = app.buttons["gold-rules"]
        let arrange = app.buttons["rack-arrange"]
        let handTiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tile-"))
        XCTAssertTrue(gold.waitForExistence(timeout: 8))
        XCTAssertTrue(gold.isHittable)
        XCTAssertTrue(handTiles.firstMatch.isHittable)
        capture("live-table-portrait")

        let table = app.otherElements["table-surface"]
        let rack = app.otherElements["table-rack"]
        let actions = app.otherElements["table-actions"]
        XCTAssertTrue(table.exists && rack.exists)
        let tableFrame = table.frame
        let rackFrame = rack.frame

        let pass = app.buttons["过"]
        let discard = app.buttons["discard-action"]
        let canAct = NSPredicate { _, _ in (pass.exists && pass.isEnabled) || (discard.exists && discard.isEnabled) }
        for _ in 0..<4 {
            wait(for: [expectation(for: canAct, evaluatedWith: app)], timeout: 15)
            if pass.exists && pass.isEnabled { pass.tap() } else { break }
        }
        XCTAssertTrue(discard.exists && discard.isEnabled)
        XCTAssertTrue(table.frame.contains(actions.frame))
        discard.tap()
        let confirmGold = app.alerts.buttons["confirm-gold-discard"]
        if confirmGold.waitForExistence(timeout: 1) { confirmGold.tap() }
        table.swipeUp()
        XCTAssertFalse(app.scrollViews["table-scroll"].exists)
        XCTAssertEqual(table.frame, tableFrame)
        XCTAssertEqual(rack.frame, rackFrame)
        if actions.exists { XCTAssertTrue(table.frame.contains(actions.frame)) }
        capture("live-table-after-discard")

        arrange.tap()
        let tile = handTiles.element(boundBy: 2)
        let tileID = tile.identifier
        tile.tap()
        XCTAssertTrue(app.buttons[tileID].isSelected)
        capture("table-portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = expectation(for: NSPredicate { _, _ in app.frame.width > app.frame.height },
                                    evaluatedWith: app)
        wait(for: [landscape], timeout: 8)
        XCTAssertTrue(gold.isHittable)
        XCTAssertTrue(app.buttons[tileID].isHittable)
        XCTAssertTrue(app.buttons[tileID].isSelected)
        capture("table-landscape")

        arrange.tap()
        gold.tap()
        XCTAssertTrue(app.staticTexts["rule-lesson-title"].waitForExistence(timeout: 5))
        capture("gold-guide-landscape")
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

    private func startSetup(_ app: XCUIApplication) {
        let start = app.buttons["start-solo-setup"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
