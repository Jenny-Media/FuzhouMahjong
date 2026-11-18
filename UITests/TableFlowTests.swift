import FuzhouCore
import XCTest

@MainActor
final class TableFlowTests: XCTestCase {
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
            let openingActions = actions.frame
            XCTAssertTrue(openingFrames.allSatisfy { $0.width > 0 && $0.height > 0 })
            capture("opening-\(orientation.rawValue)")

            skip.tap()
            XCTAssertTrue(skip.waitForNonExistence(timeout: 3))
            capture("settled-\(orientation.rawValue)")
            assertFrames([table.frame, rack.frame], match: openingFrames, labels: ["board", "rack"])
            // Claim controls can add buttons to the left of the primary action.
            XCTAssertEqual(actions.frame.maxX, openingActions.maxX, accuracy: 1)
            XCTAssertEqual(actions.frame.minY, openingActions.minY, accuracy: 1)
            XCTAssertEqual(actions.frame.height, openingActions.height, accuracy: 1)
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
            (8, 26, .discard, .south, "胡"),     // Player claims a discard after two melds.
            (5, 49, .selfDraw, .west, "自摸"),  // AI wins from its draw after two melds.
            (90013, 0, .robGold, .south, "抢金"),
            (0, 40, nil, nil, "流局"),
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

    private func launchSavedMatch(_ match: FuzhouMatch) throws -> XCUIApplication {
        let save = try JSONEncoder().encode(match).map { String(format: "%02x", $0) }.joined()
        let app = XCUIApplication()
        // Foundation reads OpenStep data literals in the launch argument domain.
        app.launchArguments = ["-play-access.archive.v1", "", "-solo-match.v2", "<\(save)>"]
        app.launch()
        let practice = app.buttons["practice-entry"]
        XCTAssertTrue(practice.waitForExistence(timeout: 5))
        XCTAssertTrue(practice.label.contains("继续单机"))
        practice.tap()
        return app
    }

    private func match(seed: UInt64, after moves: Int) throws -> FuzhouMatch {
        var random = FixtureRandom(seed: seed)
        var match = FuzhouMatch(using: &random)
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
