import FuzhouCore
import XCTest

@MainActor
final class TableFlowTests: XCTestCase {
    func testCustomRulesPreviewUpdatesForDraftChoices() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-play-access.archive.v1", "", "-table.custom-rulesets.v1", "<5b5d>", "-solo.ruleset", "pureSuit"]
        app.launch()

        let menu = app.buttons["custom-rules-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        app.buttons["manage-custom-rules"].tap()
        app.buttons["add-custom-rules"].tap()

        let indicators = element("custom-gold-indicators", in: app)
        XCTAssertTrue(indicators.waitForExistence(timeout: 5))
        indicators.tap()
        app.buttons["万筒条与风牌"].tap()
        XCTAssertTrue(element("custom-gold-explanation", in: app).label.contains("东、南、西、北"))

        let payment = element("custom-discard-payment", in: app)
        XCTAssertTrue(payment.waitForExistence(timeout: 5))
        for _ in 0..<3 where !payment.isHittable { app.swipeUp() }
        payment.tap()
        app.buttons["其余三家各付分"].tap()
        XCTAssertTrue(element("custom-payment-example", in: app).label.contains("赢家得 60 分"))

        let flush = element("custom-flush-rule", in: app)
        for _ in 0..<3 where !flush.isHittable { app.swipeUp() }
        XCTAssertTrue(flush.isHittable)
        let initialEstimate = element("custom-flush-estimate", in: app).label
        flush.tap()
        app.buttons["金按牌面"].tap()
        XCTAssertNotEqual(element("custom-flush-estimate", in: app).label, initialEstimate)

        let stacking = app.switches["叠加特殊加分"]
        for _ in 0..<3 where !stacking.isHittable { app.swipeUp() }
        XCTAssertTrue(stacking.isHittable)
        stacking.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        capture("custom-rules-examples")
        let bonus = element("custom-bonus-example", in: app)
        let combined = expectation(for: NSPredicate(format: "label CONTAINS %@", "加 300 分"), evaluatedWith: bonus)
        XCTAssertEqual(XCTWaiter.wait(for: [combined], timeout: 4), .completed, bonus.label)
        let reference = app.buttons["custom-rules-reference"]
        for _ in 0..<3 where !reference.isHittable { app.swipeUp() }
        reference.tap()
        let title = app.staticTexts["ruleset-details-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "自定义规则预览")
        let method = app.staticTexts["rule-odds-method"]
        for _ in 0..<3 where !method.isHittable { app.swipeUp() }
        XCTAssertTrue(method.label.contains("17 张随机牌"))
        XCTAssertTrue(app.staticTexts["ruleset-gold-detail"].label.contains("东、南、西、北"))
        XCTAssertTrue(element("rule-odds-robGold", in: app).exists)
        XCTAssertTrue(element("rule-odds-pureSuit", in: app).exists)
        capture("custom-rules-odds")
    }

    func testCreateAndReuseTwoCustomRulesets() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        let existing = (1...3).map { FuzhouHouseRules(name: "Existing \($0)") }
        let fixture = try JSONEncoder().encode(existing).map { String(format: "%02x", $0) }.joined()
        app.launchArguments = ["-play-access.archive.v1", "", "-table.custom-rulesets.v1", "<\(fixture)>"]
        let suffix = UUID().uuidString.prefix(4)
        let family = "Family \(suffix)"
        let friends = "Friends \(suffix)"
        app.launch()

        let menu = app.buttons["custom-rules-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        app.buttons["manage-custom-rules"].tap()
        let add = app.buttons["add-custom-rules"]
        for name in [family, friends] {
            XCTAssertTrue(add.waitForExistence(timeout: 5))
            add.tap()
            let field = app.textFields["custom-rules-name"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(name)
            if name == family { app.switches["流局连庄"].tap() }
            app.buttons["save-custom-rules"].tap()
        }
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertFalse(add.isEnabled)
        XCTAssertTrue(app.staticTexts["custom-rules-limit"].exists)
        app.buttons["完成"].tap()
        XCTAssertTrue(menu.label.contains(friends))

        app.terminate()
        app.launchArguments = ["-play-access.archive.v1", ""]
        app.launch()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertTrue(menu.label.contains(friends))
        menu.tap()
        XCTAssertTrue(app.buttons[friends].exists)
        app.buttons[family].tap()
        app.buttons["practice-entry"].tap()
        let skip = app.buttons["skip-opening"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        app.buttons["table-rules"].tap()
        let activeRules = app.staticTexts["active-ruleset"]
        XCTAssertTrue(activeRules.waitForExistence(timeout: 5))
        XCTAssertTrue(activeRules.label.contains(family))
    }

    func testNewSoloRulesetSelectionDoesNotChangeAnActiveMatch() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-play-access.archive.v1", ""]
        app.launch()

        let oldThree = app.buttons["三样加分"]
        XCTAssertTrue(oldThree.waitForExistence(timeout: 5))
        oldThree.tap()
        app.buttons["selected-ruleset-details"].tap()
        let title = app.staticTexts["ruleset-details-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "三样加分")
        let details = app.staticTexts["ruleset-pattern-detail"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertTrue(details.label.contains("清一色按普通胡牌计分"))
        app.buttons["完成"].tap()
        app.buttons["practice-entry"].tap()
        let skip = app.buttons["skip-opening"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        app.buttons["table-rules"].tap()
        let activeRules = app.staticTexts["active-ruleset"]
        XCTAssertTrue(activeRules.waitForExistence(timeout: 5))
        XCTAssertTrue(activeRules.label.contains("三样加分"))
        app.buttons["完成"].tap()
        app.buttons["BackButton"].tap()

        app.buttons["清一色加分"].tap()
        app.buttons["selected-ruleset-details"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "清一色加分")
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertTrue(details.label.contains("清一色有特殊加分"))
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["practice-entry"].label.contains("三样加分"))
        app.buttons["practice-entry"].tap()
        app.buttons["table-rules"].tap()
        XCTAssertTrue(activeRules.waitForExistence(timeout: 5))
        XCTAssertTrue(activeRules.label.contains("三样加分"))
        app.buttons["rule-contents"].tap()
        app.buttons["tutorial-ruleset-details"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "三样加分")
    }

    func testLegacySaveIsClearedAndNewTableRulesAreAvailable() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = try savedMatchArguments(FuzhouMatch(ruleset: .legacy)) +
            ["-solo.ruleset", "pureSuit", "-solo.customRulesetID", ""]
        app.launch()

        let notice = app.alerts["旧版单机牌局已清除"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        notice.buttons["好"].tap()
        let practice = app.buttons["practice-entry"]
        XCTAssertTrue(practice.waitForExistence(timeout: 5))
        XCTAssertTrue(practice.label.contains("开始新牌局"))
        XCTAssertFalse(app.buttons["saved-solo-rules"].exists)
        let newDetails = app.buttons["selected-ruleset-details"]
        newDetails.tap()
        let title = app.staticTexts["ruleset-details-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "清一色加分")
    }

    func testTwoSavedTablesRemainUntilThePlayerConfirmsWhichToKeep() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        let first = FuzhouMatch(ruleset: .oldThree)
        let second = FuzhouMatch(houseRules: .init(name: "Family", goldIndicators: .includeWinds))
        let secondSave = try JSONEncoder().encode(second).map { String(format: "%02x", $0) }.joined()
        app.launchArguments = try savedMatchArguments(first) + ["-solo-match.second.v1", "<\(secondSave)>"]
        app.launch()

        let keepFirst = app.buttons["keep-first-solo"]
        let keepSecond = app.buttons["keep-second-solo"]
        XCTAssertTrue(keepFirst.waitForExistence(timeout: 5))
        XCTAssertTrue(keepFirst.label.contains("三样加分"))
        XCTAssertTrue(keepSecond.label.contains("Family"))
        XCTAssertFalse(app.buttons["practice-entry"].exists)
        keepFirst.tap()
        let prompt = app.alerts["保留这张牌桌？"]
        let confirm = prompt.buttons["confirm-save-choice"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        prompt.buttons["取消"].firstMatch.tap()
        XCTAssertTrue(prompt.waitForNonExistence(timeout: 5))
        XCTAssertTrue(keepFirst.exists && keepSecond.exists)
        keepSecond.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        let resume = app.buttons["practice-entry"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        XCTAssertTrue(resume.label.contains("Family"))
        XCTAssertTrue(app.buttons["new-solo-game"].exists)
        XCTAssertFalse(keepFirst.exists || keepSecond.exists)
    }

    func testThrowKeepsRackInPlaceAndConfirmsGoldBeforeDiscarding() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let fixture = try match(seed: 1, after: 1)
        let state = fixture.table(for: .south)
        let drawn = try XCTUnwrap(state.drawn)
        let heldGold = try XCTUnwrap(state.hand.dropFirst(8).first(where: state.isGold))
        let app = try launchSavedMatch(fixture)
        let table = element("table-surface", in: app)
        let rack = element("table-rack", in: app)
        let actions = element("table-actions", in: app)
        let dock = element("drawn-tile-dock", in: app)
        let discard = app.buttons["discard-action"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        let frames = [table.frame, rack.frame]
        XCTAssertTrue(table.frame.contains(actions.frame))
        XCTAssertTrue(table.frame.contains(dock.frame))
        capture("turn-actions-and-drawn-dock")

        let drawnTile = app.buttons["tile-\(drawn.id)"]
        let drawnCenter = drawnTile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        drawnCenter.press(forDuration: 0.1, thenDragTo: drawnCenter.withOffset(CGVector(dx: 0, dy: -16)))
        XCTAssertTrue(drawnTile.exists)
        XCTAssertTrue(discard.isHittable)

        let goldTile = app.buttons["tile-\(heldGold.id)"]
        let goldCenter = goldTile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        goldCenter.press(forDuration: 0.1, thenDragTo: goldCenter.withOffset(CGVector(dx: 0, dy: -142)))
        let confirm = app.alerts.buttons["confirm-gold-discard"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        app.alerts.buttons["取消"].tap()
        XCTAssertTrue(goldTile.exists)

        drawnCenter.press(forDuration: 0.1, thenDragTo: drawnCenter.withOffset(CGVector(dx: 18, dy: -142)),
                          withVelocity: .slow, thenHoldForDuration: 0.15)
        XCTAssertTrue(drawnTile.waitForNonExistence(timeout: 3))
        XCTAssertTrue(element("latest-discard", in: app).label.contains("你打出"))
        assertFrames([table.frame, rack.frame], match: frames, labels: ["board", "rack"])
    }

    func testMultipleClaimActionsLeaveTheDiscardVisibleInBothOrientations() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = try launchSavedMatch(match(seed: 193, after: 1))
        let table = element("table-surface", in: app)
        let actions = element("table-actions", in: app)
        let discard = element("latest-discard", in: app)
        let pass = app.buttons["table-move-过"]
        XCTAssertTrue(pass.waitForExistence(timeout: 5))

        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let landscape = orientation == .landscapeLeft
            let resized = NSPredicate { _, _ in (app.frame.width > app.frame.height) == landscape }
            XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: resized, evaluatedWith: app)], timeout: 5), .completed)
            for label in ["吃", "碰", "杠", "过"] {
                XCTAssertTrue(app.buttons["table-move-\(label)"].isHittable, label)
            }
            XCTAssertTrue(table.frame.contains(actions.frame))
            XCTAssertTrue(discard.exists)
            XCTAssertFalse(actions.frame.intersects(discard.frame))
            capture(landscape ? "multiple-claims-landscape" : "multiple-claims-portrait")
        }
    }

    func testOpeningAndSkippingKeepTheBoardAndRackInPlace() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-play-access.archive.v1", ""]
        defer { XCUIDevice.shared.orientation = .portrait }

        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            app.launch()
            app.buttons["practice-entry"].tap()
            let skip = app.buttons["skip-opening"]
            XCTAssertTrue(skip.waitForExistence(timeout: 5))
            let table = element("table-surface", in: app)
            let rack = element("table-rack", in: app)
            let actions = element("table-actions", in: app)
            let openingFrames = [table.frame, rack.frame]
            XCTAssertFalse(actions.exists)
            XCTAssertTrue(openingFrames.allSatisfy { $0.width > 0 && $0.height > 0 })
            capture("opening-\(orientation.rawValue)")

            skip.tap()
            XCTAssertTrue(skip.waitForNonExistence(timeout: 3))
            capture("settled-\(orientation.rawValue)")
            assertFrames([table.frame, rack.frame], match: openingFrames, labels: ["board", "rack"])
            if actions.exists { XCTAssertTrue(table.frame.contains(actions.frame)) }
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tile-"))
                .firstMatch.waitForExistence(timeout: 3))
            app.terminate()
        }
    }

    func testRotationDuringTheDealSettlesOnTheCurrentTable() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-play-access.archive.v1", ""]
        app.launch()
        app.buttons["practice-entry"].tap()
        let skip = app.buttons["skip-opening"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(skip.waitForNonExistence(timeout: 8))
        let board = element("table-surface", in: app)
        XCTAssertGreaterThan(board.frame.width, board.frame.height)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tile-"))
            .firstMatch.waitForExistence(timeout: 3))
        app.terminate()
    }

    func testWinRevealAndScorecardFollowTheSameHand() throws {
        continueAfterFailure = false
        defer { XCUIDevice.shared.orientation = .portrait }
        let cases: [(seed: UInt64, moves: Int, kind: WinKind?, winner: Seat?, label: String)] = [
            (35, 41, .discard, .south, "胡"),     // Player claims a discard after two melds.
            (14, 29, .selfDraw, .west, "自摸"),   // AI wins from its draw after two melds.
            (31213, 0, .robGold, .south, "抢金"),
            (0, 36, nil, nil, "流局"),
        ]

        for (index, fixture) in cases.enumerated() {
            XCUIDevice.shared.orientation = index == 1 ? .landscapeLeft : .portrait
            let before = try match(seed: fixture.seed, after: fixture.moves)
            var completed = before
            while completed.result == nil { try playFixtureMove(in: &completed) }
            let result = try XCTUnwrap(completed.result)
            XCTAssertEqual(result.kind, fixture.kind)
            XCTAssertEqual(result.winner, fixture.winner)
            let app = try launchSavedMatch(before)
            XCTAssertFalse(app.buttons["skip-opening"].exists)

            if before.result == nil, fixture.winner == .south {
                let board = element("table-surface", in: app)
                let actions = element("table-actions", in: app)
                XCTAssertTrue(actions.waitForExistence(timeout: 5))
                XCTAssertTrue(board.frame.contains(actions.frame))
                if fixture.kind == .discard {
                    XCTAssertTrue(element("latest-discard", in: app).exists)
                    XCTAssertFalse(actions.frame.intersects(element("latest-discard", in: app).frame))
                    capture("claim-actions")
                }
                app.buttons["declare-win"].tap()
            }

            let scorecard = app.buttons["view-scorecard"]
            XCTAssertTrue(scorecard.waitForExistence(timeout: 8))
            let board = element("table-surface", in: app)
            let settledFrame = board.frame
            let outcome = result.winner == nil ? "drawn-hand" : "winning-hand-reveal"
            capture("completed-\(index)")
            XCTAssertTrue(element(outcome, in: app).exists)
            XCTAssertTrue(element(outcome, in: app).label.contains(fixture.label))
            XCTAssertFalse(app.buttons["next-hand"].exists)
            if let winner = result.winner {
                XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "revealed-winning-tile").count, 1)
                XCTAssertTrue(element("winning-pair", in: app).exists)
                for meld in completed.table(for: .south).players[winner.id].melds {
                    XCTAssertTrue(element("revealed-meld-\(meld.id)", in: app).exists)
                }
            }

            if fixture.kind == .robGold {
                XCUIDevice.shared.orientation = .landscapeLeft
                XCTAssertTrue(element(outcome, in: app).exists)
                XCTAssertTrue(scorecard.isHittable)
                XCUIDevice.shared.orientation = .portrait
            }

            scorecard.tap()
            let returnButton = app.buttons["return-to-table"]
            XCTAssertTrue(returnButton.waitForExistence(timeout: 5))
            XCTAssertTrue(app.navigationBars["本局结算"].exists)
            XCTAssertTrue(returnButton.isHittable)
            if result.winner != nil {
                XCTAssertTrue(element("winning-pair", in: app).exists)
                XCTAssertTrue(element("score-total", in: app).label.contains("\(result.points)"))
                capture("grouped-scorecard-\(index)")
            }
            XCTAssertFalse(scorecard.isHittable)
            returnButton.tap()
            XCTAssertTrue(element(outcome, in: app).waitForExistence(timeout: 5))
            assertFrames([board.frame], match: [settledFrame])

            if index == cases.count - 1 {
                scorecard.tap()
                app.buttons["next-hand"].tap()
                let skip = app.buttons["skip-opening"]
                XCTAssertTrue(skip.waitForExistence(timeout: 5))
                XCTAssertFalse(returnButton.exists)
                skip.tap()
                XCTAssertTrue(skip.waitForNonExistence(timeout: 3))
                XCTAssertFalse(scorecard.exists)
                assertFrames([board.frame], match: [settledFrame])
            }
            app.terminate()
        }
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func assertFrames(_ frames: [CGRect], match expected: [CGRect],
                              labels: [String] = ["board"],
                              file: StaticString = #filePath, line: UInt = #line) {
        for (label, (actual, original)) in zip(labels, zip(frames, expected)) {
            let difference = "\(label) moved from \(original) to \(actual)"
            XCTAssertEqual(actual.minX, original.minX, accuracy: 1, difference, file: file, line: line)
            XCTAssertEqual(actual.minY, original.minY, accuracy: 1, difference, file: file, line: line)
            XCTAssertEqual(actual.width, original.width, accuracy: 1, difference, file: file, line: line)
            XCTAssertEqual(actual.height, original.height, accuracy: 1, difference, file: file, line: line)
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func savedMatchArguments(_ match: FuzhouMatch) throws -> [String] {
        let save = try JSONEncoder().encode(match).map { String(format: "%02x", $0) }.joined()
        // Foundation reads OpenStep data literals in the launch argument domain.
        return ["-play-access.archive.v1", "", "-solo-match.v2", "<\(save)>"]
    }

    private func launchSavedMatch(_ match: FuzhouMatch) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = try savedMatchArguments(match)
        app.launch()
        let practice = app.buttons["practice-entry"]
        XCTAssertTrue(practice.waitForExistence(timeout: 5))
        XCTAssertTrue(practice.label.contains("继续单机"))
        practice.tap()
        return app
    }

    private func match(seed: UInt64, after moves: Int) throws -> FuzhouMatch {
        var random = FixtureRandom(seed: seed)
        var match = FuzhouMatch(using: &random, ruleset: .pureSuit)
        for _ in 0..<moves { try playFixtureMove(in: &match) }
        return match
    }

    private func playFixtureMove(in match: inout FuzhouMatch) throws {
        let seat = try XCTUnwrap(Seat.allCases.first { !match.legalMoves(for: $0).isEmpty })
        let moves = match.legalMoves(for: seat)
        let meld = moves.first { if case .meld = $0 { true } else { false } }
        let move: Move = moves.contains(.win) ? .win : meld ?? (moves.contains(.pass) ? .pass : moves[0])
        XCTAssertTrue(match.apply(move, by: seat))
    }
}

private struct FixtureRandom: RandomNumberGenerator {
    var seed: UInt64

    mutating func next() -> UInt64 {
        seed &+= 0x9E3779B97F4A7C15
        var result = seed
        result = (result ^ (result >> 30)) &* 0xBF58476D1CE4E5B9
        result = (result ^ (result >> 27)) &* 0x94D049BB133111EB
        return result ^ (result >> 31)
    }
}
