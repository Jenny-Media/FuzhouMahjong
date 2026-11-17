import CryptoKit
import Foundation
import XCTest
@testable import FuzhouCore

final class MatchTests: XCTestCase {
    private let completed = [1, 1, 1, 2, 3, 4, 5, 6, 7].map { TileKind(.characters, $0) }
        + [2, 3, 4, 7, 7].map { TileKind(.circles, $0) }
        + [3, 4, 5].map { TileKind(.bamboo, $0) }

    func testTileInventoryAndWildSubstitution() {
        XCTAssertEqual(Tile.fullSet.count, 144)
        XCTAssertEqual(Set(Tile.fullSet.map(\.id)).count, 144)
        XCTAssertEqual(Tile.fullSet.filter(\.kind.isFlower).count, 36)
        let gold = TileKind(.bamboo, 8)
        XCTAssertTrue(WinningHand.isComplete(completed, gold: gold))
        XCTAssertTrue(WinningHand.isComplete(completed.dropLast() + [gold], gold: gold))
        XCTAssertFalse(WinningHand.isComplete(Array(completed.dropLast()), gold: gold))
        XCTAssertFalse(WinningHand.isComplete(completed.dropLast() + [TileKind(.circles, 1)], gold: gold))
        XCTAssertTrue(TileKind(.season, 2).matchesGold(TileKind(.flower, 1)))
        XCTAssertFalse(TileKind(.wind, 2).matchesGold(TileKind(.flower, 1)))
    }

    func testRobGoldDuringOpeningDoesNotCountFlippedTileAsHeldGold() throws {
        let indicator = try XCTUnwrap(completed.last)
        let waiting = Array(completed.dropLast())
        var match = try fixture(hands: [.south: waiting], gold: indicator, draws: [.init(.bamboo, 9)])
        XCTAssertEqual(match.table(for: .south).step, .opening)
        XCTAssertTrue(match.apply(.win, by: .south))
        passEveryoneElse(&match, except: .south)
        let result = try XCTUnwrap(match.result)
        XCTAssertEqual(result.kind, .robGold)
        XCTAssertEqual(result.winner, .south)
        XCTAssertEqual(result.lines.map(\.name), ["基础分", "抢金"])
        XCTAssertEqual(result.delta(for: .south), 180)
    }

    func testDiscardWinChargesOnlyDiscarder() throws {
        let killer = TileKind(.bamboo, 5)
        var match = try fixture(hands: [.south: Array(completed.dropLast())],
                                gold: .init(.bamboo, 9), draws: [killer])
        resolveOpening(&match)
        let draw = try XCTUnwrap(match.drawn)
        XCTAssertTrue(match.apply(.discard(draw.id), by: .east))
        XCTAssertTrue(match.apply(.win, by: .south))
        passEveryoneElse(&match, except: .south)
        let result = try XCTUnwrap(match.result)
        XCTAssertEqual(result.winner, .south)
        XCTAssertEqual(result.kind, .discard)
        XCTAssertEqual(result.source, .east)
        XCTAssertEqual(Seat.allCases.map(result.delta), [-10, 10, 0, 0])
    }

    func testOpenKongBeatsChowAndDrawsAReplacement() throws {
        let suited = (1...9).map { TileKind(.circles, $0) } + (1...5).map { TileKind(.bamboo, $0) }
        let south = [.init(.characters, 3), .init(.characters, 4)] + suited
        let west = Array(repeating: TileKind(.characters, 5), count: 3)
            + (1...9).map { TileKind(.characters, $0) }.filter { $0.rank != 5 }
            + (6...9).map { TileKind(.bamboo, $0) } + [.init(.circles, 9)]
        var match = try fixture(hands: [.south: south, .west: west],
                                gold: .init(.circles, 1), draws: [.init(.characters, 5)])
        resolveOpening(&match)
        let firstDraw = try XCTUnwrap(match.table(for: .south).lastDraw)
        XCTAssertEqual(firstDraw.seat, .east)
        XCTAssertFalse(firstDraw.fromReserve)
        let discarded = try XCTUnwrap(match.drawn)
        XCTAssertTrue(match.apply(.discard(discarded.id), by: .east))
        let chow = try XCTUnwrap(match.legalMoves(for: .south).first {
            if case .meld(.chow, _) = $0 { true } else { false }
        })
        let kong = try XCTUnwrap(match.legalMoves(for: .west).first {
            if case .meld(.openKong, _) = $0 { true } else { false }
        })
        XCTAssertTrue(match.apply(chow, by: .south))
        XCTAssertTrue(match.apply(kong, by: .west))
        passEveryoneElse(&match, except: .west)
        let table = match.table(for: .west)
        XCTAssertEqual(table.current, .west)
        XCTAssertNotNil(table.drawn)
        XCTAssertEqual(table.hand.count, 13)
        XCTAssertEqual(table.players[Seat.west.id].melds.first?.kind, .openKong)
        XCTAssertTrue(table.players[Seat.east.id].discards.isEmpty)
        let replacement = try XCTUnwrap(table.lastDraw)
        XCTAssertEqual(replacement.seat, .west)
        XCTAssertTrue(replacement.fromReserve)
        XCTAssertEqual(replacement.sequence, firstDraw.sequence + 1)
        let otherSeat = match.table(for: .south)
        XCTAssertEqual(otherSeat.lastDraw, replacement)
        XCTAssertNil(otherSeat.drawn)
        XCTAssertEqual(otherSeat.players[Seat.west.id].melds.first?.tiles.count, 4)
        XCTAssertEqual(table.latestDiscard, TableDiscard(seat: .east, tile: discarded))
        let nextTile = try XCTUnwrap(table.drawn)
        XCTAssertTrue(match.apply(.discard(nextTile.id), by: .west))
        XCTAssertEqual(match.table(for: .south).discardTimeline, [
            TableDiscard(seat: .east, tile: discarded), TableDiscard(seat: .west, tile: nextTile),
        ])
    }

    func testScoringLinesAndPayments() {
        let tiles = completed.enumerated().map { Tile(id: $0.offset, kind: $0.element) }
        let flowers = [Tile(id: 99, kind: .init(.wind, 1))]
        let lines = FuzhouScoring.lines(hand: tiles, melds: [], flowers: flowers, gold: .init(.bamboo, 9),
                                        dealer: true, continuation: 2, openingDraw: true, kind: .selfDraw)
        XCTAssertEqual(lines.map(\.points), [10, 2, 4, 15, 50])
        let result = RoundResult(winner: .east, kind: .selfDraw, source: nil,
                                 winningTile: tiles.last, lines: lines)
        XCTAssertEqual(result.points, 81)
        XCTAssertEqual(Seat.allCases.map(result.delta), [243, -81, -81, -81])
    }

    func testComputerKeepsItsWaitInsteadOfDiscardingTheIsolatedLookingPairOfNeighbors() throws {
        var match = try fixture(hands: [.east: Array(completed.dropLast())],
                                gold: .init(.bamboo, 9), draws: [.init(.circles, 8)])
        resolveOpening(&match)
        let extra = try XCTUnwrap(match.drawn)
        let (seat, move) = try XCTUnwrap(match.nextComputerMove(excluding: [.south, .west, .north]))
        XCTAssertEqual(seat, .east)
        XCTAssertEqual(move, .discard(extra.id))
    }

    func testComputerChowsToMakeAReadyHand() throws {
        let hand = [1, 1, 1, 2, 3, 4, 9].map { TileKind(.characters, $0) }
            + [2, 3, 4, 7, 7].map { TileKind(.circles, $0) }
            + [3, 5, 7, 8].map { TileKind(.bamboo, $0) }
        var match = try fixture(hands: [.south: hand], gold: .init(.circles, 9), draws: [.init(.bamboo, 4)])
        resolveOpening(&match)
        let offered = try XCTUnwrap(match.drawn)
        XCTAssertTrue(match.apply(.discard(offered.id), by: .east))
        let (seat, move) = try XCTUnwrap(match.nextComputerMove(excluding: [.east, .west, .north]))
        XCTAssertEqual(seat, .south)
        guard case .meld(.chow, _) = move else { return XCTFail("Expected a chow, got \(move)") }
        XCTAssertTrue(match.apply(move, by: .south))
    }

    func testGoldDiscardRestrictionIsVisibleToTheDiscarder() throws {
        let gold = TileKind(.bamboo, 9)
        var match = try fixture(hands: [:], gold: gold, draws: [gold])
        resolveOpening(&match)
        XCTAssertFalse(match.table(for: .east).viewerMustSelfDraw)
        let tile = try XCTUnwrap(match.drawn)
        XCTAssertTrue(match.apply(.discard(tile.id), by: .east))
        XCTAssertTrue(match.table(for: .east).viewerMustSelfDraw)
        XCTAssertFalse(match.table(for: .south).viewerMustSelfDraw)
    }

    func testSeededGamesSettleAndRoundStateResumes() throws {
        for seed in UInt64(0)..<50 {
            var random = TestRandom(seed: seed)
            var match = FuzhouMatch(using: &random)
            for _ in 0..<250 where match.result == nil {
                let (seat, move) = try XCTUnwrap(match.nextComputerMove(excluding: []))
                XCTAssertTrue(match.apply(move, by: seat))
            }
            XCTAssertNotNil(match.result, "seed \(seed)")
            XCTAssertEqual(match.scores.reduce(0, +), 0)
            XCTAssertEqual(try JSONDecoder().decode(FuzhouMatch.self, from: JSONEncoder().encode(match)), match)

            let firstDealer = match.dealer
            let repeats = match.result?.winner == firstDealer
            match.nextRound()
            XCTAssertEqual(match.roundNumber, 2)
            XCTAssertEqual(match.dealer, repeats ? firstDealer : firstDealer.advanced(1))
            XCTAssertEqual(match.scores.reduce(0, +), 0)
        }
    }

    func testNearbySeatReservationAndPrivateSnapshot() throws {
        var host = NearbyMatch(hostName: "阿榕")
        let key = UUID()
        XCTAssertEqual(host.join(key: key, name: "小林"), .south)
        XCTAssertTrue(host.start())
        let east = try XCTUnwrap(host.update(for: .east).table)
        let south = try XCTUnwrap(host.update(for: .south).table)
        XCTAssertEqual(east.viewer, .east)
        XCTAssertEqual(south.viewer, .south)
        XCTAssertTrue(Set(east.hand).isDisjoint(with: Set(south.hand)))
        if east.current == .east { XCTAssertNil(south.drawn) }
        XCTAssertNil(host.join(key: UUID(), name: "陌生玩家"))

        let stale = host.revision
        host.disconnect(.south)
        XCTAssertTrue(host.paused)
        XCTAssertFalse(host.advanceComputer())
        XCTAssertEqual(host.join(key: key, name: "同一玩家"), .south)
        XCTAssertFalse(host.paused)
        XCTAssertEqual(host.update(for: .south).table, south)
        XCTAssertFalse(host.submit(.pass, seat: .south, basedOn: stale))
    }

    func testEncryptedFramesRejectReplayAndWrongSession() throws {
        let a = Curve25519.KeyAgreement.PrivateKey()
        let b = Curve25519.KeyAgreement.PrivateKey()
        let room = UUID()
        var host = try NearbyCipher(own: a, peer: b.publicKey.rawRepresentation, room: room, host: true)
        var guest = try NearbyCipher(own: b, peer: a.publicKey.rawRepresentation, room: room, host: false)
        var wrong = try NearbyCipher(own: b, peer: a.publicKey.rawRepresentation, room: UUID(), host: false)
        let clear = Data("only your hand".utf8)
        let sealed = try host.seal(clear)
        XCTAssertNotEqual(clear, sealed)
        XCTAssertEqual(try guest.open(sealed), clear)
        XCTAssertThrowsError(try guest.open(sealed))
        XCTAssertThrowsError(try wrong.open(sealed))
        XCTAssertEqual(try host.open(guest.seal(clear)), clear)
    }

    private func passEveryoneElse(_ match: inout FuzhouMatch, except player: Seat) {
        for seat in Seat.allCases where seat != player && match.legalMoves(for: seat).contains(.pass) {
            XCTAssertTrue(match.apply(.pass, by: seat))
        }
    }

    private func resolveOpening(_ match: inout FuzhouMatch) {
        for seat in Seat.allCases where match.table(for: seat).step == .opening && match.legalMoves(for: seat).contains(.pass) {
            XCTAssertTrue(match.apply(.pass, by: seat))
        }
        XCTAssertEqual(match.table(for: .east).step, .turn)
    }

    private func fixture(hands: [Seat: [TileKind]], gold: TileKind, draws: [TileKind]) throws -> FuzhouMatch {
        var available = Tile.fullSet
        func take(_ kind: TileKind) throws -> Tile {
            let i = try XCTUnwrap(available.firstIndex { $0.kind == kind }, "fixture has too many \(kind)")
            return available.remove(at: i)
        }
        let indicator = try take(gold)
        let drawTiles = try draws.map(take)
        var starting: [Seat: [Tile]] = [:]
        for seat in Seat.allCases {
            if let specified = hands[seat] {
                XCTAssertEqual(specified.count, 16)
                starting[seat] = try specified.map(take)
            }
        }
        for seat in Seat.allCases where starting[seat] == nil {
            starting[seat] = []
            for _ in 0..<16 {
                let i = try XCTUnwrap(available.firstIndex { !$0.kind.isFlower })
                starting[seat]?.append(available.remove(at: i))
            }
        }
        let spare = available.removeLast()
        let reserve = Array(available.suffix(16)) + [indicator, spare]
        available.removeLast(16)
        let dealOrder = (0..<16).flatMap { index in Seat.allCases.map { starting[$0]![index] } }
        return FuzhouMatch(deck: available + drawTiles.reversed() + dealOrder.reversed() + reserve)
    }
}

private struct TestRandom: RandomNumberGenerator {
    var seed: UInt64

    mutating func next() -> UInt64 {
        seed &+= 0x9E3779B97F4A7C15
        var mixed = seed
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58476D1CE4E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D049BB133111EB
        return mixed ^ (mixed >> 31)
    }
}
