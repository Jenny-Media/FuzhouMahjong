@testable import FuzhouCore
import SwiftUI
import XCTest
@testable import FuzhouMahjong

@MainActor
final class TablePresentationTests: XCTestCase {
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
