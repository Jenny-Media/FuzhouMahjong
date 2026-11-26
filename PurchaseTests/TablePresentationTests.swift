@testable import FuzhouCore
import SwiftUI
import XCTest
@testable import FuzhouMahjong

@MainActor
final class TablePresentationTests: XCTestCase {
    func testRobGoldLessonMatchesTheDealersOpeningHand() {
        let discard = "庄家要先选一张牌打出"
        let legacy = RuleLesson.gold.detail(for: .legacy, houseRules: nil)
        XCTAssertTrue(legacy.contains("庄家和闲家都把翻出的牌直接加进手牌"))
        XCTAssertFalse(legacy.contains(discard))
        for ruleset in [FuzhouRuleset.oldThree, .pureSuit] {
            XCTAssertTrue(RuleLesson.gold.detail(for: ruleset, houseRules: nil).contains(discard))
        }
    }

    func testAnOpeningConcealedKongDoesNotImplyADiscard() {
        var table = FuzhouMatch().table(for: .east)
        table.discardTimeline = nil
        let tiles = Array(Tile.fullSet.prefix(4))
        table.players[0].melds = [Meld(kind: .concealedKong, tiles: tiles, from: nil)]
        XCTAssertFalse(table.hasKnownDiscard)
        table.players[0].melds = [Meld(kind: .openKong, tiles: tiles, from: .south)]
        XCTAssertTrue(table.hasKnownDiscard)
    }

    func testOpeningStagesShowOnlyWhatHasHappenedUnderTheHouseRules() {
        for indicators in FuzhouHouseRules.GoldIndicators.allCases {
            let rules = FuzhouHouseRules(name: "测试", goldIndicators: indicators)
            var table = FuzhouMatch(houseRules: rules).table(for: .east)
            table.openingIndicatorFlowerIDs = []
            for index in table.players.indices { table.players[index].flowerCount = 0 }
            table.players[0].flowerCount = 1
            let stages = OpeningDeal.Stage.afterDeal(at: table)
            if indicators == .suitedOnly {
                XCTAssertEqual(stages, [.flowers(goldRevealed: false), .revealGold(flowersShown: true)])
                XCTAssertFalse(stages[0].showsGold)
            } else {
                XCTAssertEqual(stages, [.revealGold(flowersShown: false), .flowers(goldRevealed: true)])
                XCTAssertFalse(stages[0].showsFlowers)
            }
            XCTAssertTrue(stages[1].showsGold)
            XCTAssertTrue(stages[1].showsFlowers)
            for index in table.players.indices { table.players[index].flowerCount = 0 }
            XCTAssertEqual(OpeningDeal.Stage.afterDeal(at: table), [.revealGold(flowersShown: false)])
        }
    }

    func testIndicatorCreditsAreShownAtTheGoldReveal() throws {
        let flower = try XCTUnwrap(Tile.fullSet.first { $0.kind.isFlower })
        let flip = try XCTUnwrap(Tile.fullSet.last { $0.kind.isFlower && $0.id != flower.id })
        for indicators in [FuzhouHouseRules.GoldIndicators.suitedOnly, .includeHonors] {
            let rules = FuzhouHouseRules(name: "测试", goldIndicators: indicators)
            var table = FuzhouMatch(houseRules: rules).table(for: .east)
            for index in table.players.indices {
                table.players[index].exposedFlowers = []
                table.players[index].flowerCount = 0
            }
            table.openingIndicatorFlowerIDs = [flip.id]
            table.players[0].exposedFlowers = [flip]
            table.players[0].flowerCount = 1
            let onlyGold = OpeningDeal.Stage.afterDeal(at: table)
            XCTAssertEqual(onlyGold, [.revealGold(flowersShown: false)])
            XCTAssertEqual(onlyGold.first?.presenting(table.players[0], indicatorFlowers: [flip.id]).exposedFlowers, [flip])
            table.players[0].exposedFlowers = [flower, flip]
            table.players[0].flowerCount = 2
            let stages = OpeningDeal.Stage.afterDeal(at: table)
            let visible = stages.map { $0.presenting(table.players[0], indicatorFlowers: [flip.id]).exposedFlowers ?? [] }
            XCTAssertEqual(visible, [indicators.revealsBeforeFlowers ? [flip] : [flower], [flower, flip]])
        }
    }

    func testOldHostDefersDealerFlowersWithUnknownOrigins() throws {
        let flower = try XCTUnwrap(Tile.fullSet.first { $0.kind.isFlower })
        for indicators in [FuzhouHouseRules.GoldIndicators.suitedOnly, .includeHonors] {
            let rules = FuzhouHouseRules(name: "测试", goldIndicators: indicators)
            var table = FuzhouMatch(houseRules: rules).table(for: .south)
            table.openingIndicatorFlowerIDs = nil
            table.lastDraw = nil
            for i in table.players.indices { table.players[i].flowerCount = 0 }
            table.players[table.dealer.id].flowerCount = 1
            table.players[table.dealer.id].exposedFlowers = [flower]
            let dealer = table.players[table.dealer.id]
            let stages = OpeningDeal.Stage.afterDeal(at: table)
            XCTAssertEqual(stages, [.revealGold(flowersShown: false)])
            let creditIDs = table.openingIndicatorCredits(for: dealer.seat)
            XCTAssertNil(creditIDs)
            let atReveal = try XCTUnwrap(stages.first?.presenting(dealer, indicatorFlowers: creditIDs))
            XCTAssertEqual(atReveal.flowerCount, 0)
            XCTAssertEqual(atReveal.exposedFlowers, [])
            XCTAssertEqual(dealer.flowerCount, 1)

            table.players[Seat.south.id].flowerCount = 1
            let guest = table.players[Seat.south.id]
            XCTAssertEqual(table.openingIndicatorCredits(for: guest.seat), [])
            XCTAssertTrue(OpeningDeal.Stage.afterDeal(at: table).contains(.flowers(goldRevealed: indicators.revealsBeforeFlowers)))

            table.openingIndicatorFlowerIDs = []
            table.players[Seat.south.id].flowerCount = 0
            XCTAssertTrue(OpeningDeal.Stage.afterDeal(at: table).contains(.flowers(goldRevealed: indicators.revealsBeforeFlowers)))
        }
    }

    func testRackEndSwipeKeepsTrackingWhenItCurvesInward() {
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            for edge in [HorizontalEdge.leading, .trailing] {
                let inward: CGFloat = (edge == .leading) == (direction == .leftToRight) ? 1 : -1
                var swipe = RackTile.DiscardSwipe()
                let start = CGSize(width: inward * 12, height: -8)
                swipe.track(start, edge: edge, direction: direction)
                XCTAssertTrue(swipe.isTracking)
                XCTAssertFalse(swipe.canReleaseDiscard(start))

                let curveEnd = CGSize(width: inward * 92, height: -50)
                swipe.track(curveEnd, edge: edge, direction: direction)
                XCTAssertTrue(swipe.canReleaseDiscard(curveEnd))
                XCTAssertFalse(swipe.canReleaseDiscard(CGSize(width: inward * 20, height: -14)))
            }
        }
    }

    func testPartialRackRowEndsUseThePaneCenter() {
        let edge = RackTile.DiscardSwipe.rackEdge
        XCTAssertEqual(edge(8, 10, 8, 8), .leading)
        XCTAssertEqual(edge(9, 10, 8, 8), .leading)
        XCTAssertEqual(edge(12, 13, 8, 8), .trailing)
        XCTAssertNil(edge(9, 13, 8, 8))
        XCTAssertEqual(edge(7, 10, 8, 8), .trailing)

        // The draw slot shares the center of the pane with a single-row rack.
        XCTAssertEqual(edge(6, 7, 16, 17), .leading)
        XCTAssertNil(edge(8, 9, 16, 17))
        XCTAssertEqual(edge(9, 10, 16, 17), .trailing)
    }

    func testRackDiscardSwipeRequiresAnUpwardStartAndEnoughRise() {
        let rejected: [(HorizontalEdge?, CGSize)] = [
            (.leading, CGSize(width: 100, height: -10)),
            (.trailing, CGSize(width: 62, height: -62)),
            (nil, CGSize(width: 62, height: -62))
        ]
        for (edge, translation) in rejected {
            var swipe = RackTile.DiscardSwipe()
            swipe.track(translation, edge: edge, direction: .leftToRight)
            XCTAssertFalse(swipe.isTracking)
            XCTAssertFalse(swipe.canReleaseDiscard(translation))
        }

        var swipe = RackTile.DiscardSwipe()
        let short = CGSize(width: 4, height: -16)
        swipe.track(short, edge: .leading, direction: .leftToRight)
        XCTAssertTrue(swipe.isTracking)
        XCTAssertFalse(swipe.canReleaseDiscard(short))
        let flick = CGSize(width: 10, height: -24)
        XCTAssertFalse(swipe.canReleaseDiscard(flick))

        XCTAssertTrue(swipe.canReleaseDiscard(CGSize(width: 10, height: -48)))
        XCTAssertFalse(swipe.canReleaseDiscard(CGSize(width: 10, height: -47.9)))
    }

    func testHeldMeldSwipeKeepsCheckingTheUpwardAngle() {
        let swipe = RackTile.MeldSwipe(isDrawn: false, direction: .leftToRight)
        let upward = CGSize(width: 0, height: -62)
        XCTAssertTrue(swipe.isUpward(upward))
        XCTAssertTrue(swipe.canRelease(upward, predictedEnd: upward))

        let diagonal = CGSize(width: 62, height: -62)
        XCTAssertFalse(swipe.isUpward(diagonal))
        XCTAssertFalse(swipe.canRelease(diagonal, predictedEnd: diagonal))

        let sideways = CGSize(width: 140, height: -50)
        XCTAssertFalse(swipe.isUpward(sideways))
        XCTAssertFalse(swipe.canRelease(sideways, predictedEnd: sideways))
    }

    func testMeldSwipeKeepsDrawnTileAllowanceAndFlickThreshold() {
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            let swipe = RackTile.MeldSwipe(isDrawn: true, direction: direction)
            let horizontal: CGFloat = direction == .leftToRight ? -62 : 62
            let inward = CGSize(width: horizontal, height: -62)
            let outward = CGSize(width: -horizontal, height: -62)
            XCTAssertTrue(swipe.canRelease(inward, predictedEnd: inward))
            XCTAssertFalse(swipe.canRelease(outward, predictedEnd: outward))
        }

        let swipe = RackTile.MeldSwipe(isDrawn: false, direction: .leftToRight)
        let flick = CGSize(width: 10, height: -24)
        XCTAssertTrue(swipe.canRelease(flick, predictedEnd: CGSize(width: 16, height: -80)))
        XCTAssertFalse(swipe.canRelease(flick, predictedEnd: flick))
        XCTAssertFalse(swipe.canRelease(CGSize(width: 0, height: -21), predictedEnd: CGSize(width: 0, height: -80)))
    }

    func testFoldAtAWindowEdgeKeepsTheTableAndRackInOnePane() {
        let size = CGSize(width: 350, height: 600)
        let examples: [(CGRect, CGRect)] = [
            (CGRect(x: -14, y: -30, width: 28, height: 660), CGRect(x: 14, y: 0, width: 336, height: 600)),
            (CGRect(x: 336, y: -30, width: 28, height: 660), CGRect(x: 0, y: 0, width: 336, height: 600)),
            (CGRect(x: 1, y: -30, width: 16, height: 660), CGRect(x: 17, y: 0, width: 333, height: 600)),
            (CGRect(x: -30, y: 586, width: 410, height: 28), CGRect(x: 0, y: 0, width: 350, height: 586)),
            (CGRect(x: -28, y: -30, width: 28, height: 660), CGRect(origin: .zero, size: size))
        ]
        for (division, expectedFrame) in examples {
            XCTAssertFalse(FoldRegions.hasInteriorDivision(in: size, divisions: [division]))
            XCTAssertEqual(FoldRegions.contentFrame(in: size, avoiding: [division]), expectedFrame)
        }
    }

    func testFoldAcrossTheWindowPreservesBookAndTabletopPanes() {
        let book = CGSize(width: 660, height: 600)
        let vertical = CGRect(x: 321, y: -28, width: 18, height: 656)
        XCTAssertTrue(FoldRegions.hasInteriorDivision(in: book, divisions: [vertical]))

        let tabletop = CGSize(width: 660, height: 660)
        let horizontal = CGRect(x: -28, y: 321, width: 716, height: 18)
        XCTAssertTrue(FoldRegions.hasInteriorDivision(in: tabletop, divisions: [horizontal]))
    }

    func testConsecutiveFlowerRevealsKeepTheirOwnExpiry() throws {
        let start = ContinuousClock.now
        let flowers = Array(Tile.fullSet.lazy.filter { $0.kind.isFlower }.prefix(10))
        let west = TableState.Player(seat: .west, rackCount: 16, flowerCount: flowers.count,
                                     discards: [], melds: [], score: 0, exposedFlowers: flowers)
        let first = Set(flowers.suffix(4).map(\.id))
        let next: Set<Tile.ID> = [try XCTUnwrap(Tile.fullSet.last).id]
        var highlights = FlowerHighlights()
        highlights.reveal(first, at: start)
        highlights.reveal(next, at: start + .milliseconds(200))

        XCTAssertEqual(highlights.nextExpiry, start + .milliseconds(900))
        let row = FlowerStripLayout(west, highlighted: highlights.tiles, width: 75, height: 19)
        XCTAssertTrue(first.isSubset(of: Set(row.tiles.map(\.id))))
        XCTAssertEqual(highlights.tiles, first.union(next))

        highlights.expire(at: start + .milliseconds(900))
        XCTAssertEqual(highlights.tiles, next)
        XCTAssertEqual(highlights.nextExpiry, start + .milliseconds(1_100))
        highlights.expire(at: start + .milliseconds(1_100))
        XCTAssertTrue(highlights.tiles.isEmpty)
        XCTAssertNil(highlights.nextExpiry)
    }

    func testCompactFlowerRowKeepsTheFullReplacementChainVisible() {
        let flowers = Array(Tile.fullSet.lazy.filter { $0.kind.isFlower }.prefix(10))
        let player = TableState.Player(seat: .west, rackCount: 16, flowerCount: flowers.count,
                                       discards: [], melds: [], score: 0, exposedFlowers: flowers)
        let newlyRevealed = flowers.suffix(3)
        for width in [CGFloat(38), 75] {
            let cue = Set(newlyRevealed.map(\.id))
            let highlighted = FlowerStripLayout(player, highlighted: cue, width: width, height: 19)
            XCTAssertTrue(cue.isSubset(of: Set(highlighted.tiles.map(\.id))))
            XCTAssertGreaterThan(highlighted.tileWidth, 0)
            XCTAssertEqual(highlighted.hiddenCount + highlighted.tiles.count, flowers.count)

            let settled = FlowerStripLayout(player, highlighted: [], width: width, height: 19)
            XCTAssertEqual(settled.tiles.last, flowers.last)
            XCTAssertLessThan(settled.tiles.count, flowers.count)
        }
    }

    func testOpponentDrawAppearsInTheRackOnlyWhenItLands() {
        var table = FuzhouMatch().table(for: .south)
        table.step = .turn
        table.current = .east
        var player = table.players[Seat.east.id]
        for (total, melds) in [(17, 0), (14, 1)] {
            if melds > 0 {
                player.melds = [Meld(kind: .openKong, tiles: Array(Tile.fullSet.prefix(4)), from: .south)]
            }
            player.rackCount = total
            let flying = OpponentRackCounts(player, at: table, pendingDraw: .east, reduceMotion: false)
            XCTAssertEqual(flying.total, total)
            XCTAssertEqual(flying.landed, total - 1)
            XCTAssertEqual(OpponentRackCounts(player, at: table, pendingDraw: nil, reduceMotion: false).landed, total)
            XCTAssertEqual(OpponentRackCounts(player, at: table, pendingDraw: .east, reduceMotion: true).landed, total)
        }
        table.step = .claim
        XCTAssertEqual(OpponentRackCounts(player, at: table, pendingDraw: .east, reduceMotion: false).landed, 14)
    }

    func testRenderedOpponentRackGainsOneBackAtLandingWithAndWithoutAMeld() throws {
        var table = FuzhouMatch().table(for: .south)
        table.step = .turn
        table.current = .east
        let actor = Seat.east.id
        let size = CGSize(width: 600, height: 240)
        func render(pending: Seat?) throws -> Data {
            let board = LiveTable(table: table, names: [:], latest: nil, opening: nil, drawingFromReserve: nil,
                                  pendingDraw: pending, paused: false, size: size, showsDrawDock: false,
                                  flyingDiscard: nil, flyingClaim: nil, inspectedSeat: .constant(nil),
                                  onOfferedTileFrame: { _, _ in }) { EmptyView() } drawDock: { EmptyView() }
            return try XCTUnwrap(ImageRenderer(content: board).uiImage?.pngData())
        }

        for total in [17, 14] {
            if total == 14 {
                table.players[actor].melds = [Meld(kind: .openKong, tiles: Array(Tile.fullSet.prefix(4)), from: .south)]
            }
            table.players[actor].rackCount = total - 1
            let before = try render(pending: nil)
            table.players[actor].rackCount = total
            let inFlight = try render(pending: .east)
            let landed = try render(pending: nil)
            XCTAssertTrue(before == inFlight, "The stationary rack gained a back during flight (\(total) tiles)")
            XCTAssertTrue(inFlight != landed, "The rack did not gain a visible back on landing (\(total) tiles)")
        }
    }

    func testGuestSeatInspectorDismissesWhenHostDealsAgain() async throws {
        var game = FuzhouMatch()
        while game.result == nil, let (seat, move) = game.nextComputerMove(excluding: []) {
            XCTAssertTrue(game.apply(move, by: seat))
        }
        XCTAssertNotNil(game.result)
        let model = InspectorFixture(table: game.table(for: .south))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: InspectorBoard(model: model))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        model.selection = .east
        try await waitFor { controller.presentedViewController != nil }
        game.nextRound()
        model.table = game.table(for: .south)
        try await waitFor { model.selection == nil && controller.presentedViewController == nil }
    }

    private func waitFor(_ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(30)) }
        XCTAssertTrue(condition(), file: file, line: line)
    }
}

final class NearbyNicknameTests: XCTestCase {
    func testGeneratedNicknamePersistsAndExistingNicknameIsPreserved() throws {
        let domain = "NearbyNicknameTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }

        NearbyNickname.prepareStoredName(in: defaults)
        let generated = try XCTUnwrap(defaults.string(forKey: NearbyNickname.storageKey))
        XCTAssertEqual(generated.count, 2)
        XCTAssertTrue(generated.allSatisfy(\.isLetter))
        NearbyNickname.prepareStoredName(in: defaults)
        XCTAssertEqual(defaults.string(forKey: NearbyNickname.storageKey), generated)

        defaults.set("  牌友  ", forKey: NearbyNickname.storageKey)
        NearbyNickname.prepareStoredName(in: defaults)
        XCTAssertEqual(defaults.string(forKey: NearbyNickname.storageKey), "  牌友  ")

        defaults.set("ABCDEFGHIJKLMN", forKey: NearbyNickname.storageKey)
        NearbyNickname.prepareStoredName(in: defaults)
        XCTAssertEqual(defaults.string(forKey: NearbyNickname.storageKey), "ABCDEFGHIJKLMN")

        for unusable in [" \n\t", "\u{2060}"] {
            defaults.set(unusable, forKey: NearbyNickname.storageKey)
            NearbyNickname.prepareStoredName(in: defaults)
            let replacement = try XCTUnwrap(defaults.string(forKey: NearbyNickname.storageKey))
            XCTAssertEqual(replacement.count, 2)
            XCTAssertNotEqual(replacement, "牌友")
        }
    }
}

@MainActor @Observable
private final class InspectorFixture {
    var table: TableState
    var selection: Seat?
    init(table: TableState) { self.table = table }
}

private struct InspectorBoard: View {
    @Bindable var model: InspectorFixture

    var body: some View {
        GeometryReader { geometry in
            LiveTable(table: model.table, names: [:], latest: nil, opening: nil, drawingFromReserve: nil,
                      paused: false, size: geometry.size, showsDrawDock: false, flyingDiscard: nil, flyingClaim: nil,
                      inspectedSeat: $model.selection, onOfferedTileFrame: { _, _ in }) {
                EmptyView()
            } drawDock: { EmptyView() }
        }
    }
}
