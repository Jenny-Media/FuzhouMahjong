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
        let reveal = try XCTUnwrap(WinningHand.groups(for: result, melds: [], gold: indicator))
        XCTAssertEqual(reveal.count, 6)
        XCTAssertTrue(reveal[0].members.contains { $0.id == result.winningTile?.id })
        XCTAssertTrue(reveal.flatMap(\.members).allSatisfy { $0.represents == nil })
    }

    func testDealerCanRobGoldBySwappingADealtTileAndCanPassWithoutDrawingAgain() throws {
        let indicator = TileKind(.bamboo, 5)
        let extra = TileKind(.bamboo, 4)
        let spare = TileKind(.bamboo, 9)
        let hand = completed.filter { $0 != indicator && $0 != extra } + [spare]
        let opening = try fixture(hands: [.east: hand], gold: indicator, draws: [extra, .init(.bamboo, 8)], ruleset: .pureSuit)
        let table = opening.table(for: .east)
        let drawn = try XCTUnwrap(table.drawn)
        let discard = try XCTUnwrap(table.hand.first { $0.kind == spare })
        XCTAssertEqual(table.step, .opening)
        XCTAssertEqual(table.hand.count, 16)
        XCTAssertEqual(drawn.kind, extra)
        XCTAssertEqual(table.lastDraw?.isOpeningDeal, true)
        XCTAssertTrue(table.moves.contains(.win))
        XCTAssertTrue(table.canSubmit(.discard(discard.id)))
        XCTAssertFalse(table.canSubmit(.discard(drawn.id)))
        XCTAssertNil(opening.table(for: .south).robGoldDiscardIDs)
        XCTAssertNil(opening.table(for: .south).drawn)

        var passing = try JSONDecoder().decode(FuzhouMatch.self, from: JSONEncoder().encode(opening))
        resolveOpening(&passing)
        XCTAssertEqual(passing.drawn, drawn)
        XCTAssertEqual(passing.table(for: .east).remaining, table.remaining)
        XCTAssertEqual(passing.table(for: .east).lastDraw, table.lastDraw)

        var winning = opening
        XCTAssertFalse(winning.apply(.discard(drawn.id), by: .east))
        XCTAssertTrue(winning.apply(.discard(discard.id), by: .east))
        passEveryoneElse(&winning, except: .east)
        let result = try XCTUnwrap(winning.result)
        XCTAssertEqual(result.kind, .robGold)
        XCTAssertEqual(result.winningHand.count, 17)
        XCTAssertTrue(result.winningHand.contains(drawn))
        XCTAssertFalse(result.winningHand.contains(discard))
        XCTAssertEqual(result.winningTile, opening.gold)
        XCTAssertEqual(winning.table(for: .east).latestDiscard, TableDiscard(seat: .east, tile: discard))
        XCTAssertNotNil(WinningHand.groups(for: result, melds: [], gold: indicator))

        var automatic = opening
        XCTAssertTrue(automatic.apply(.win, by: .east))
        passEveryoneElse(&automatic, except: .east)
        XCTAssertEqual(automatic.result, result)
    }

    func testDealerReplacesAFlowerInTheSeventeenthSlotBeforeFlippingGold() throws {
        let indicator = TileKind(.bamboo, 9)
        let replacement = TileKind(.circles, 9)
        var match = try fixture(hands: [:], gold: indicator, draws: [.init(.season, 1)], ruleset: .pureSuit,
                                openingTail: [.init(.flower, 1), replacement])
        resolveOpening(&match)
        let table = match.table(for: .east)
        XCTAssertEqual(table.gold?.kind, indicator)
        XCTAssertEqual(table.drawn?.kind, replacement)
        XCTAssertEqual(table.players.first?.flowerCount, 2)
        XCTAssertEqual(table.players.first?.exposedFlowers?.map(\.kind), [.init(.season, 1), .init(.flower, 1)])
        XCTAssertEqual(match.table(for: .south).players.first?.exposedFlowers, table.players.first?.exposedFlowers)
        XCTAssertEqual(table.lastDraw?.flowersReplaced, 2)
        XCTAssertEqual(table.lastDraw?.fromReserve, true)
    }

    func testFlowerProjectionAcceptsOlderHostsWithOnlyACount() throws {
        let player = TableState.Player(seat: .east, rackCount: 17, flowerCount: 2, discards: [], melds: [], score: 0)
        let data = try JSONEncoder().encode(player)
        let decoded = try JSONDecoder().decode(TableState.Player.self, from: data)
        XCTAssertEqual(decoded.flowerCount, 2)
        XCTAssertNil(decoded.exposedFlowers)
    }

    func testGuestRobGoldKeepsDealerExtraAndOldOpeningSavesCanFinish() throws {
        let indicator = TileKind(.bamboo, 5)
        let waiting = Array(completed.dropLast())
        let opening = try fixture(hands: [.south: waiting], gold: indicator,
                                  draws: [.init(.bamboo, 9)], ruleset: .pureSuit)
        let dealerDraw = try XCTUnwrap(opening.drawn)
        XCTAssertEqual(opening.table(for: .south).step, .opening)

        var winning = opening
        XCTAssertTrue(winning.apply(.win, by: .south))
        passEveryoneElse(&winning, except: .south)
        XCTAssertEqual(winning.result?.winner, .south)
        XCTAssertEqual(winning.table(for: .east).drawn, dealerDraw)
        XCTAssertNil(winning.table(for: .south).drawn)

        let data = try JSONEncoder().encode(opening)
        var oldFields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let extra = try XCTUnwrap(oldFields.removeValue(forKey: "drawn"))
        oldFields["wall"] = try XCTUnwrap(oldFields["wall"] as? [Any]) + [extra]
        oldFields.removeValue(forKey: "lastDraw")
        oldFields.removeValue(forKey: "openingDealerGoldDiscards")
        oldFields["drew"] = [] as [Int]
        oldFields["firstDraw"] = false
        var resumed = try JSONDecoder().decode(FuzhouMatch.self, from: JSONSerialization.data(withJSONObject: oldFields))
        XCTAssertNil(resumed.drawn)
        resolveOpening(&resumed)
        XCTAssertEqual(resumed.drawn, dealerDraw)
        XCTAssertNil(resumed.table(for: .east).lastDraw?.isOpeningDeal)
    }

    func testBuiltInOpeningCreditsFlippedHonorsAndFlowersToDealer() throws {
        let gold = TileKind(.bamboo, 9)
        let bonusFlips = [TileKind(.wind, 4), .init(.dragon, 2), .init(.season, 1)]
        for ruleset in FuzhouRuleset.builtIn {
            var match = try fixture(hands: [:], gold: gold, draws: [.init(.circles, 9)],
                                    ruleset: ruleset, openingTail: bonusFlips)
            XCTAssertEqual(match.gold?.kind, gold)
            resolveOpening(&match)
            let table = match.table(for: .east)
            XCTAssertEqual(table.ruleset, ruleset)
            XCTAssertEqual(table.players.map(\.flowerCount), [3, 0, 0, 0])
            XCTAssertEqual(table.players.first?.exposedFlowers?.map(\.kind), bonusFlips)
            XCTAssertEqual(table.openingIndicatorFlowerIDs, table.players.first?.exposedFlowers?.map(\.id))
            XCTAssertEqual(table.drawn?.kind, .init(.circles, 9))
            XCTAssertTrue(table.hand.allSatisfy { !$0.kind.isFlower })
        }
    }

    func testBuiltInThreeGoldWinsWithoutACompleteHand() throws {
        let gold = TileKind(.bamboo, 9)
        let loose = [1, 2, 4, 5, 7].map { TileKind(.characters, $0) }
            + [1, 2, 4, 5, 7].map { TileKind(.circles, $0) }
            + [1, 2, 4, 7].map { TileKind(.bamboo, $0) }
        XCTAssertFalse(WinningHand.isComplete(loose + [gold, gold, gold], gold: gold))
        for ruleset in FuzhouRuleset.builtIn {
            var match = try fixture(hands: [.east: loose + [gold, gold]], gold: gold, draws: [gold], ruleset: ruleset)
            resolveOpening(&match)
            XCTAssertTrue(match.table(for: .east).canDeclareThreeGold)
            XCTAssertFalse(match.table(for: .south).canDeclareThreeGold)
            XCTAssertTrue(match.apply(.win, by: .east))
            let result = try XCTUnwrap(match.result)
            XCTAssertEqual(result.kind, .selfDraw)
            XCTAssertEqual(result.patterns, [.threeGold])
            XCTAssertEqual(result.lines.last, .init(name: "三金倒", points: 40))
            XCTAssertEqual(result.winningHand.count(where: { $0.kind == gold }), 3)
            XCTAssertNil(WinningHand.groups(for: result, melds: [], gold: gold))
        }
    }

    func testCustomWindAndDragonGoldAreKeptDuringOpeningAndCanWinOrBeDiscarded() throws {
        let loose = [1, 2, 4, 5, 7].map { TileKind(.characters, $0) }
            + [1, 2, 4, 5, 7].map { TileKind(.circles, $0) }
            + [1, 2, 4].map { TileKind(.bamboo, $0) }
        let east = TileKind(.wind, 1)
        let white = TileKind(.dragon, 3)
        let season = TileKind(.season, 3)
        for (option, gold, other) in [(FuzhouHouseRules.GoldIndicators.includeWinds, east, white),
                                       (.includeDragons, white, east), (.includeHonors, east, white)] {
            let rules = FuzhouHouseRules(name: "家庭", goldIndicators: option)
            let tail = option == .includeHonors ? [season] : [other, season]
            var match = try fixture(hands: [.east: loose + [gold, gold, other]], gold: gold, draws: [gold],
                                    ruleset: .pureSuit, openingTail: tail, houseRules: rules)
            let table = match.table(for: .east)
            let drawn = try XCTUnwrap(table.drawn)
            XCTAssertEqual(table.gold?.kind, gold)
            XCTAssertEqual(table.hand.filter(table.isGold).count, 2)
            XCTAssertFalse(table.hand.contains(where: { $0.kind == other }))
            XCTAssertEqual(table.hand.count, 16)
            XCTAssertEqual(drawn.kind, gold)
            XCTAssertTrue(table.canDeclareThreeGold)
            XCTAssertFalse(table.moves.contains(.replaceFlower(drawn.id)))
            var discarding = match
            XCTAssertTrue(discarding.apply(.discard(drawn.id), by: .east))
            XCTAssertTrue(discarding.table(for: .east).viewerMustSelfDraw)
            XCTAssertTrue(match.apply(.win, by: .east))
            XCTAssertTrue(try XCTUnwrap(match.result).patterns.contains(.threeGold))
        }
    }

    func testOldCustomRulesDecodeWithSuitedGoldAndNewRulesRoundTrip() throws {
        var rules = FuzhouHouseRules(name: "家庭", flush: .faceValue)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let oldShape = try encoder.encode(rules)
        let oldFields = try XCTUnwrap(JSONSerialization.jsonObject(with: oldShape) as? [String: Any])
        XCTAssertNil(oldFields["additionalGoldIndicators"])
        XCTAssertEqual(try decoder.decode(FuzhouHouseRules.self, from: oldShape).goldIndicators, .suitedOnly)
        rules.goldIndicators = .includeWinds
        XCTAssertEqual(try decoder.decode(FuzhouHouseRules.self, from: encoder.encode(rules)), rules)
    }

    func testOpeningOddsUseTheConfiguredIndicatorPoolAndFlushRule() throws {
        let standard = FuzhouOpeningOdds(flush: .wildcard)
        let faceValue = FuzhouOpeningOdds(flush: .faceValue)
        let honors = FuzhouOpeningOdds(flush: .wildcard, goldIndicators: .includeHonors)
        XCTAssertEqual(standard.atLeastTwoGoldInRack, 0.05783812378769176, accuracy: 1e-14)
        XCTAssertEqual(standard.threeGoldInRack, 0.0028213718920825246, accuracy: 1e-14)
        XCTAssertEqual(honors.windIndicatorChance, 16.0 / 136, accuracy: 1e-14)
        XCTAssertEqual(honors.dragonIndicatorChance, 12.0 / 136, accuracy: 1e-14)
        XCTAssertLessThan(honors.atLeastTwoGoldInRack, standard.atLeastTwoGoldInRack)
        let robGold = try XCTUnwrap(standard.probability(of: .robGold))
        XCTAssertEqual(robGold, 3.1962412133121037e-5, accuracy: 1e-18)
        XCTAssertEqual(try XCTUnwrap(honors.probability(of: .robGold)), robGold * 108 / 136, accuracy: 1e-18)
        XCTAssertEqual(try XCTUnwrap(standard.probability(of: .goldenPair)), 1.3121673207922498e-6, accuracy: 1e-19)
        XCTAssertEqual(try XCTUnwrap(standard.probability(of: .pureSuit)), 3.0634078377464516e-9, accuracy: 1e-22)
        XCTAssertEqual(try XCTUnwrap(faceValue.probability(of: .pureSuit)), 1.735358939513297e-10, accuracy: 1e-23)
        XCTAssertNil(FuzhouOpeningOdds(flush: .disabled).probability(of: .pureSuit))
    }

    func testBuiltInResultsShowBothPatternsForOffSuitGoldPairFlush() throws {
        let gold = TileKind(.bamboo, 9)
        let oneSuit = [1, 2, 3, 2, 3, 4, 4, 5, 6, 6, 7, 8, 7, 8, 9].map { TileKind(.characters, $0) }
        for ruleset in FuzhouRuleset.builtIn {
            var match = try fixture(hands: [.east: Array(oneSuit.dropLast()) + [gold, gold]],
                                    gold: gold, draws: [try XCTUnwrap(oneSuit.last)], ruleset: ruleset)
            resolveOpening(&match)
            XCTAssertTrue(match.apply(.win, by: .east))
            let result = try XCTUnwrap(match.result)
            let groups = try XCTUnwrap(WinningHand.groups(for: result, melds: [], gold: gold))
            let pair = try XCTUnwrap(groups.first { $0.kind == .pair })
            XCTAssertEqual(pair.members.map(\.tile.kind), [gold, gold])
            if ruleset == .pureSuit {
                XCTAssertEqual(result.patterns, [.goldenPair, .pureSuit])
                XCTAssertTrue(pair.members.allSatisfy { $0.represents?.suit == .characters })
                XCTAssertFalse(result.lines.contains { $0.name == WinPattern.goldenPair.title })
                XCTAssertEqual(result.lines.last, .init(name: "清一色", points: 240))
            } else {
                XCTAssertEqual(result.patterns, [.goldenPair])
                XCTAssertEqual(result.lines.last, .init(name: "金雀（金对）", points: 60))
            }
        }
    }

    func testBuiltInFlushIncludesExposedMelds() {
        let kind = TileKind(.bamboo, 9)
        let gold = Tile(id: 100, kind: kind)
        let remainder = [1, 2, 3, 2, 3, 4, 4, 5, 6, 6, 7, 8].map { TileKind(.characters, $0) } + [kind, kind]
        let hand = remainder.enumerated().map { Tile(id: $0.offset, kind: $0.element) }
        for suit in [Suit.characters, .circles] {
            let chow = (7...9).map { Tile(id: $0 + 20, kind: .init(suit, $0)) }
            let result = FuzhouScoring.modern(hand: hand, melds: [Meld(kind: .chow, tiles: chow, from: .east)],
                                               flowers: [], gold: gold, dealer: false, continuation: 0,
                                               kind: .discard, ruleset: .pureSuit)
            XCTAssertEqual(result.patterns, suit == .characters ? [.goldenPair, .pureSuit] : [.goldenPair])
        }
    }

    func testBuiltInGoldPairBeatsNearerOrdinaryClaim() throws {
        let west = [1, 2, 3, 4, 5, 6].map { TileKind(.circles, $0) }
            + [3, 4, 5, 6, 7, 8].map { TileKind(.characters, $0) }
            + [3, 4, 9, 9].map { TileKind(.bamboo, $0) }
        var match = try fixture(hands: [.south: Array(completed.dropLast()), .west: west],
                                gold: .init(.bamboo, 9), draws: [.init(.bamboo, 5)], ruleset: .oldThree)
        resolveOpening(&match)
        XCTAssertTrue(match.apply(.discard(try XCTUnwrap(match.drawn).id), by: .east))
        XCTAssertTrue(match.apply(.win, by: .south))
        XCTAssertNil(match.result)
        XCTAssertEqual(match.table(for: .south).discardClaimFeedback, .pending(.win))
        XCTAssertTrue(match.apply(.win, by: .west))
        passEveryoneElse(&match, except: .west)
        XCTAssertEqual(match.result?.winner, .west)
        XCTAssertEqual(match.result?.patterns, [.goldenPair])
        XCTAssertEqual(match.table(for: .south).discardClaimFeedback, .overridden(.win, by: .win))
    }

    func testDiscardWinSettlesWithoutWaitingForPungAndExplainsAnEarlierPung() throws {
        let offered = TileKind(.bamboo, 5)
        let south = [offered, offered] + (1...9).map { TileKind(.characters, $0) }
            + [1, 3, 5, 6, 9].map { TileKind(.circles, $0) }
        var match = try fixture(hands: [.south: south, .west: Array(completed.dropLast())],
                                gold: .init(.bamboo, 9), draws: [offered], ruleset: .pureSuit)
        resolveOpening(&match)
        XCTAssertTrue(match.apply(.discard(try XCTUnwrap(match.drawn).id), by: .east))
        if match.legalMoves(for: .north).contains(.pass) { XCTAssertTrue(match.apply(.pass, by: .north)) }
        let pung = try XCTUnwrap(match.legalMoves(for: .south).first {
            if case .meld(.pung, _) = $0 { true } else { false }
        })
        XCTAssertFalse(match.legalMoves(for: .south).contains(.win))

        var winningFirst = match
        XCTAssertTrue(winningFirst.apply(.win, by: .west))
        XCTAssertEqual(winningFirst.result?.winner, .west)
        XCTAssertFalse(winningFirst.apply(pung, by: .south))
        XCTAssertNil(winningFirst.table(for: .south).discardClaimFeedback)

        XCTAssertTrue(match.apply(pung, by: .south))
        XCTAssertEqual(match.table(for: .south).discardClaimFeedback, .pending(pung))
        XCTAssertNil(match.table(for: .west).discardClaimFeedback)
        XCTAssertTrue(match.table(for: .south).players[Seat.south.id].melds.isEmpty)
        let saved = try JSONEncoder().encode(match)
        match = try JSONDecoder().decode(FuzhouMatch.self, from: saved)
        XCTAssertEqual(match.table(for: .south).discardClaimFeedback, .pending(pung))

        var passing = match
        XCTAssertTrue(passing.apply(.pass, by: .west))
        XCTAssertEqual(passing.table(for: .south).players[Seat.south.id].melds.first?.kind, .pung)
        XCTAssertNil(passing.table(for: .south).discardClaimFeedback)

        XCTAssertTrue(match.apply(.win, by: .west))
        XCTAssertEqual(match.result, winningFirst.result)
        XCTAssertEqual(match.table(for: .south).discardClaimFeedback, .overridden(pung, by: .win))
        XCTAssertNil(match.table(for: .west).discardClaimFeedback)
        match.nextRound()
        XCTAssertNil(match.table(for: .south).discardClaimFeedback)
    }

    func testDiscardWinsAtEqualPriorityWaitForTheEarlierSeat() throws {
        let west = [1, 2, 3, 4, 5, 6].map { TileKind(.circles, $0) }
            + [3, 4, 5, 6, 7, 8].map { TileKind(.characters, $0) }
            + [3, 4, 9, 9].map { TileKind(.bamboo, $0) }
        var match = try fixture(hands: [.south: Array(completed.dropLast()), .west: west],
                                gold: .init(.bamboo, 8), draws: [.init(.bamboo, 5)], ruleset: .pureSuit)
        resolveOpening(&match)
        XCTAssertTrue(match.apply(.discard(try XCTUnwrap(match.drawn).id), by: .east))
        XCTAssertTrue(match.apply(.win, by: .west))
        XCTAssertNil(match.result)
        XCTAssertFalse(match.settleRestoredDiscard())
        XCTAssertTrue(match.legalMoves(for: .south).contains(.win))
        XCTAssertTrue(match.apply(.win, by: .south))
        XCTAssertEqual(match.result?.winner, .south)
        XCTAssertEqual(match.table(for: .west).discardClaimFeedback, .overridden(.win, by: .win))
    }

    func testSavesWithoutARulesetKeepLegacyRules() throws {
        XCTAssertEqual(FuzhouMatch().ruleset, .pureSuit)
        var legacy = try fixture(hands: [:], gold: .init(.wind, 4), draws: [])
        let archived = try JSONEncoder().encode(legacy)
        XCTAssertFalse(String(decoding: archived, as: UTF8.self).contains("matchRuleset"))
        legacy = try JSONDecoder().decode(FuzhouMatch.self, from: archived)
        XCTAssertEqual(legacy.ruleset, .legacy)
        XCTAssertEqual(legacy.gold?.kind, .init(.wind, 4))
    }

    func testCustomDiscardSettlementCanChargeAllThreeOpponents() throws {
        for payment in FuzhouHouseRules.DiscardPayment.allCases {
            let rules = FuzhouHouseRules(name: "周末", discardPayment: payment, flush: .disabled)
            var match = try fixture(hands: [.south: Array(completed.dropLast())], gold: .init(.bamboo, 9),
                                    draws: [.init(.bamboo, 5)], ruleset: .oldThree, houseRules: rules)
            resolveOpening(&match)
            XCTAssertTrue(match.apply(.discard(try XCTUnwrap(match.drawn).id), by: .east))
            XCTAssertTrue(match.apply(.win, by: .south))
            passEveryoneElse(&match, except: .south)
            let result = try XCTUnwrap(match.result)
            XCTAssertEqual(result.kind, .discard)
            let expected = payment == .discarder ? [-10, 10, 0, 0] : [-10, 30, -10, -10]
            XCTAssertEqual(Seat.allCases.map(result.delta), expected)
            XCTAssertEqual(match.scores, expected)
        }
    }

    func testMidMatchDrawChangesTheStreakOnlyForTheReturningDealer() throws {
        for keepDealer in [false, true] {
            let rules = FuzhouHouseRules(name: "测试", keepDealerOnDraw: keepDealer)
            let encoder = JSONEncoder()
            let game = FuzhouMatch(houseRules: rules)
            var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(game)) as? [String: Any])
            saved["continuation"] = 2
            saved["step"] = "finished"
            saved["result"] = try JSONSerialization.jsonObject(with: encoder.encode(RoundResult.draw))
            var match = try JSONDecoder().decode(FuzhouMatch.self, from: JSONSerialization.data(withJSONObject: saved))
            match.nextRound()
            XCTAssertEqual(match.dealer, keepDealer ? .east : .south)
            XCTAssertEqual(match.continuation, keepDealer ? 3 : 0)
            XCTAssertEqual(match.roundNumber, 2)
        }
    }

    func testOlderMatchFinishesUnderItsOriginalDealerRules() throws {
        var ready = try fixture(hands: [.east: Array(completed.dropLast())], gold: .init(.bamboo, 9),
                                draws: [try XCTUnwrap(completed.last)], ruleset: .pureSuit)
        resolveOpening(&ready)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        func archive(_ game: FuzhouMatch) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(game)) as? [String: Any])
        }
        func load(_ archive: [String: Any]) throws -> FuzhouMatch {
            try decoder.decode(FuzhouMatch.self, from: JSONSerialization.data(withJSONObject: archive))
        }

        var saved = try archive(ready)
        saved.removeValue(forKey: "resetsStreakOnPassingDraw")
        saved["dealerTurns"] = 4
        saved["roundNumber"] = 7
        saved["continuation"] = 6
        saved["scores"] = [66, -22, -22, -22]
        var old = try load(saved)
        XCTAssertEqual(old.scores, [66, -22, -22, -22])
        XCTAssertEqual(old.continuation, 6)
        XCTAssertNil(old.table(for: .south).resetsStreakOnPassingDraw)
        XCTAssertTrue(old.apply(.win, by: .east))
        XCTAssertEqual(old.result?.delta(for: .east), (10 + 6 * 2) * 3)
        let settledScores = old.scores
        old = try decoder.decode(FuzhouMatch.self, from: encoder.encode(old))
        old.nextRound()
        XCTAssertEqual(old.scores, settledScores)
        XCTAssertEqual(old.dealer, .east)
        XCTAssertEqual(old.continuation, 7)

        let draw = try JSONSerialization.jsonObject(with: encoder.encode(RoundResult.draw))
        saved = try archive(old)
        saved["step"] = "finished"
        saved["result"] = draw
        old = try load(saved)
        old.nextRound()
        XCTAssertEqual(old.dealer, .south)
        XCTAssertEqual(old.continuation, 8)
        XCTAssertEqual(old.scores, settledScores)
        XCTAssertNil(old.table(for: .east).resetsStreakOnPassingDraw)

        // Finishing the last dealer's hand starts a new match on the current rules.
        saved["dealer"] = Seat.north.id
        saved["dealerTurns"] = 15
        old = try load(saved)
        XCTAssertTrue(old.matchFinished)
        old.nextRound()
        XCTAssertEqual(old.table(for: .east).resetsStreakOnPassingDraw, true)
        XCTAssertEqual(old.roundNumber, 1)
        XCTAssertEqual(old.continuation, 0)
        XCTAssertEqual(old.scores, [0, 0, 0, 0])
    }

    func testCustomDrawCanRepeatFinalDealerAndRulesSurviveSaveAndNewMatch() throws {
        let encoder = JSONEncoder()
        for keepDealer in [false, true] {
            var rules = FuzhouHouseRules(name: "家庭玩法", keepDealerOnDraw: keepDealer)
            let match = FuzhouMatch(houseRules: rules)
            rules.name = "后来改的名称"
            var snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(match)) as? [String: Any])
            snapshot["dealerTurns"] = 15
            snapshot["step"] = "finished"
            snapshot["result"] = try JSONSerialization.jsonObject(with: encoder.encode(RoundResult.draw))
            var reloaded = try JSONDecoder().decode(FuzhouMatch.self, from: JSONSerialization.data(withJSONObject: snapshot))
            XCTAssertEqual(reloaded.matchFinished, !keepDealer)
            reloaded.nextRound()
            XCTAssertEqual(reloaded.roundNumber, keepDealer ? 2 : 1)
            XCTAssertEqual(reloaded.continuation, keepDealer ? 1 : 0)
            XCTAssertEqual(reloaded.dealerTurns, keepDealer ? 15 : 0)
            XCTAssertEqual(reloaded.table(for: .south).houseRules?.name, "家庭玩法")
            XCTAssertEqual(reloaded.houseRules?.id, rules.id)
        }
    }

    func testCustomWildcardsAndBonusStackingAffectTheSameWinningHand() throws {
        let gold = TileKind(.bamboo, 9)
        let oneSuit = [1, 2, 3, 2, 3, 4, 4, 5, 6, 6, 7, 8, 7, 8, 9].map { TileKind(.characters, $0) }
        for flush in FuzhouHouseRules.Flush.allCases {
            let rules = FuzhouHouseRules(name: "周末", flush: flush, stackBonuses: true)
            var match = try fixture(hands: [.east: Array(oneSuit.dropLast()) + [gold, gold]], gold: gold,
                                    draws: [try XCTUnwrap(oneSuit.last)], ruleset: rules.baseRuleset, houseRules: rules)
            resolveOpening(&match)
            XCTAssertTrue(match.apply(.win, by: .east))
            let result = try XCTUnwrap(match.result)
            XCTAssertEqual(result.patterns, flush == .wildcard ? [.goldenPair, .pureSuit] : [.goldenPair])
            XCTAssertEqual(result.lines.first { $0.name == WinPattern.goldenPair.title }?.points, 60)
            XCTAssertEqual(result.lines.first { $0.name == WinPattern.pureSuit.title }?.points, flush == .wildcard ? 240 : nil)
        }
    }

    func testFaceValueFlushShowsTheNaturalGroupsAndOnlyCompatibleBonuses() throws {
        let gold = TileKind(.characters, 9)
        let ranks = [1, 2, 3, 1, 2, 3, 4, 5, 6, 4, 5, 6, 1, 1]
        let natural = ranks.map { TileKind(.characters, $0) }
        let rules = FuzhouHouseRules(name: "原牌清一色", flush: .faceValue, stackBonuses: true)
        var match = try fixture(hands: [.east: natural + [gold, gold]], gold: gold, draws: [gold],
                                ruleset: .pureSuit, houseRules: rules)
        resolveOpening(&match)
        XCTAssertTrue(match.apply(.win, by: .east))
        let result = try XCTUnwrap(match.result)
        XCTAssertEqual(result.patterns, [.threeGold, .pureSuit])
        let groups = try XCTUnwrap(WinningHand.groups(for: result, melds: [], gold: gold))
        XCTAssertTrue(groups.flatMap(\.members).allSatisfy { $0.represents == nil })
        XCTAssertTrue(groups.contains { $0.kind == .triplet && $0.members.map(\.tile.kind) == [gold, gold, gold] })
    }

    func testWinningGroupsShowThePairWinningCopyAndGoldSubstitutionWithOpenSets() throws {
        let north = TileKind(.wind, 4)
        let winningKind = TileKind(.circles, 6)
        let hand = [
            TileKind(.bamboo, 5), north, TileKind(.bamboo, 7), winningKind, winningKind,
        ].enumerated().map { Tile(id: $0.offset, kind: $0.element) }
        let melds = (1...4).map { rank in
            let kind: MeldKind = rank == 4 ? .openKong : .pung
            let tiles = (0..<(rank == 4 ? 4 : 3)).map { Tile(id: rank * 10 + $0, kind: TileKind(.characters, rank)) }
            return Meld(kind: kind, tiles: tiles, from: .east)
        }
        let result = RoundResult(winner: .north, kind: .discard, source: .east,
                                 winningTile: hand[4], winningHand: hand, lines: [])

        let reveal = try XCTUnwrap(WinningHand.groups(for: result, melds: melds, gold: north))
        XCTAssertEqual(reveal.map(\.kind), [.pair, .sequence, .meld(.pung), .meld(.pung), .meld(.pung), .meld(.openKong)])
        XCTAssertEqual(Set(reveal[0].members.map(\.id)), [3, 4])
        XCTAssertEqual(reveal[1].members.map { $0.represents ?? $0.tile.kind },
                       [5, 6, 7].map { TileKind(.bamboo, $0) })
        XCTAssertEqual(reveal[1].members.first { $0.tile.kind == north }?.represents, TileKind(.bamboo, 6))
        XCTAssertEqual(reveal.last?.members.map(\.tile), melds.last?.tiles)
        let displayed = reveal.flatMap(\.members).map(\.id)
        XCTAssertEqual(displayed.sorted(), (hand + melds.flatMap(\.tiles)).map(\.id).sorted())
    }

    func testWinningGroupsShowTheScoredGoldPairAndSequences() throws {
        let gold = TileKind(.wind, 4)
        let hand = ([1, 2, 3].map { TileKind(.bamboo, $0) } + [gold, gold])
            .enumerated().map { Tile(id: $0.offset, kind: $0.element) }
        let melds = (1...4).map { rank in
            Meld(kind: .chow, tiles: (rank...(rank + 2)).map {
                Tile(id: rank * 10 + $0, kind: TileKind(.characters, $0))
            }, from: .east)
        }
        let lines = FuzhouScoring.lines(hand: hand, melds: melds, flowers: [], gold: gold,
                                        dealer: false, continuation: 0, openingDraw: false, kind: .selfDraw)
        XCTAssertTrue(lines.contains { $0.name == "金对" })
        XCTAssertTrue(lines.contains { $0.name == "平胡" })
        let result = RoundResult(winner: .south, kind: .selfDraw, source: nil,
                                 winningTile: hand[4], winningHand: hand, lines: lines)
        let reveal = try XCTUnwrap(WinningHand.groups(for: result, melds: melds, gold: gold))
        XCTAssertEqual(reveal.map(\.kind), [.pair, .sequence] + Array(repeating: .meld(.chow), count: 4))
        XCTAssertEqual(reveal[0].members.map { $0.tile.kind }, [gold, gold])
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
        var afterChow = match
        XCTAssertTrue(afterChow.apply(chow, by: .south))
        passEveryoneElse(&afterChow, except: .south)
        let claimant = afterChow.table(for: .south)
        XCTAssertNil(claimant.drawn)
        XCTAssertEqual(afterChow.table(for: .east).players[Seat.south.id].rackCount, claimant.hand.count)

        XCTAssertTrue(match.apply(chow, by: .south))
        XCTAssertEqual(match.table(for: .south).discardClaimFeedback, .pending(chow))
        XCTAssertTrue(match.apply(kong, by: .west))
        passEveryoneElse(&match, except: .west)
        let table = match.table(for: .west)
        XCTAssertEqual(match.table(for: .south).discardClaimFeedback, .overridden(chow, by: kong))
        XCTAssertEqual(table.current, .west)
        XCTAssertNotNil(table.drawn)
        XCTAssertEqual(table.hand.count, 13)
        let observer = match.table(for: .north)
        XCTAssertEqual(observer.players[Seat.west.id].rackCount, 14)
        XCTAssertNil(observer.drawn)
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
        XCTAssertNil(match.table(for: .south).discardClaimFeedback)
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

    func testComputerPassesPungsThatBreakReadyHandsFromSeeds50And53() throws {
        let cases: [(hand: [TileKind], opened: TileKind, offered: TileKind, gold: TileKind)] = [
            ([4, 4].map { TileKind(.characters, $0) } + [1, 2, 3, 3, 4, 5].map { TileKind(.circles, $0) }
                + [5, 6, 7, 7, 7].map { TileKind(.bamboo, $0) },
             TileKind(.characters, 2), TileKind(.circles, 3), TileKind(.bamboo, 9)),
            ([4, 4, 5, 5, 7, 8, 9].map { TileKind(.characters, $0) } + [5, 6, 7, 7, 8, 9].map { TileKind(.circles, $0) },
             TileKind(.bamboo, 9), TileKind(.circles, 7), TileKind(.circles, 1))
        ]
        let filler = TileKind(.bamboo, 1)
        for example in cases {
            let rack = example.hand + [example.opened, example.opened, filler]
            var match = try fixture(hands: [.west: rack], gold: example.gold,
                                    draws: [example.opened, example.offered], ruleset: .pureSuit)
            resolveOpening(&match)
            XCTAssertTrue(match.apply(.discard(try XCTUnwrap(match.drawn).id), by: .east))
            passEveryoneElse(&match, except: .west)
            let pung = try XCTUnwrap(match.legalMoves(for: .west).first { if case .meld(.pung, _) = $0 { true } else { false } })
            XCTAssertTrue(match.apply(pung, by: .west))
            let spare = try XCTUnwrap(match.table(for: .west).hand.first { $0.kind == filler })
            XCTAssertTrue(match.apply(.discard(spare.id), by: .west))
            passEveryoneElse(&match, except: .west)
            XCTAssertEqual(match.drawn?.kind, example.offered)
            XCTAssertTrue(match.apply(.discard(try XCTUnwrap(match.drawn).id), by: .north))
            XCTAssertTrue(match.legalMoves(for: .west).contains { if case .meld(.pung, _) = $0 { true } else { false } })
            XCTAssertEqual(match.nextComputerMove(excluding: [.east, .south, .north])?.1, .pass)
        }
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
            let ruleset: FuzhouRuleset = seed.isMultiple(of: 2) ? .pureSuit : .oldThree
            var match = FuzhouMatch(using: &random, ruleset: ruleset)
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
            XCTAssertEqual(match.ruleset, ruleset)
            XCTAssertEqual(match.roundNumber, 2)
            XCTAssertEqual(match.dealer, repeats ? firstDealer : firstDealer.advanced(1))
            XCTAssertEqual(match.scores.reduce(0, +), 0)
        }
    }

    func testVersionOneSnapshotsShowTheSameConcealedCountAsTheOwnersHand() throws {
        // Replay both published v1 encodings without the newer discriminator.
        func check(_ match: FuzhouMatch, file: StaticString = #filePath, line: UInt = #line) throws {
            let actor = match.current
            let owner = match.table(for: actor)
            let total = owner.hand.count + (owner.drawn == nil ? 0 : 1)
            let observer = match.table(for: actor.advanced(1))
            XCTAssertNil(observer.drawn, file: file, line: line)
            for sent in Set([owner.hand.count, total]) {
                var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(observer)) as? [String: Any])
                json.removeValue(forKey: "rackCountsIncludeDrawnTile")
                var players = try XCTUnwrap(json["players"] as? [[String: Any]])
                players[actor.id]["rackCount"] = sent
                json["players"] = players
                let decoded = try JSONDecoder().decode(TableState.self, from: JSONSerialization.data(withJSONObject: json))
                XCTAssertEqual(decoded.concealedCount(for: decoded.players[actor.id]), total, file: file, line: line)
                for player in decoded.players where player.seat != actor {
                    XCTAssertEqual(decoded.concealedCount(for: player), player.rackCount, file: file, line: line)
                }
            }
        }

        for ruleset in [FuzhouRuleset.pureSuit, .legacy] {
            var opening = try fixture(hands: [.south: Array(completed.dropLast())],
                                      gold: .init(.bamboo, 5), draws: [.init(.bamboo, 9)], ruleset: ruleset)
            XCTAssertEqual(opening.table(for: .south).step, .opening)
            try check(opening)
            XCTAssertTrue(opening.apply(.win, by: .south))
            passEveryoneElse(&opening, except: .south)
            XCTAssertEqual(opening.result?.kind, .robGold)
            try check(opening)

            var random = TestRandom(seed: 1)
            var game = FuzhouMatch(using: &random, ruleset: ruleset)
            try check(game)
            while let (seat, move) = game.nextComputerMove(excluding: []) {
                XCTAssertTrue(game.apply(move, by: seat))
                try check(game)
            }
        }
    }

    func testOpponentCountFollowsTheExtraDrawWithoutRevealingItsFace() throws {
        var random = TestRandom(seed: 1)
        var match = FuzhouMatch(using: &random)
        for _ in 0..<13 {
            let seat = try XCTUnwrap(Seat.allCases.first { !match.legalMoves(for: $0).isEmpty })
            let moves = match.legalMoves(for: seat)
            let claim = moves.first { if case .meld = $0 { true } else { false } }
            let move: Move = moves.contains(.win) ? .win : claim ?? (moves.contains(.pass) ? .pass : moves[0])
            XCTAssertTrue(match.apply(move, by: seat))
            if match.current == .north && match.table(for: .north).players[3].melds.first?.kind == .pung {
                let owner = match.table(for: .north)
                XCTAssertEqual(match.table(for: .south).players[3].rackCount, owner.hand.count + (owner.drawn == nil ? 0 : 1))
            }
        }
        let owner = match.table(for: .north)
        let draw = try XCTUnwrap(owner.drawn)
        XCTAssertEqual(owner.hand.count, 13)
        XCTAssertEqual(owner.players[Seat.north.id].melds.first?.kind, .pung)
        XCTAssertNil(match.table(for: .south).drawn)
        XCTAssertEqual(match.table(for: .south).players[Seat.north.id].rackCount, 14)
        XCTAssertTrue(match.apply(.discard(draw.id), by: .north))
        XCTAssertEqual(match.table(for: .south).players[Seat.north.id].rackCount, 13)
    }

    func testNearbyNameNormalizationProducesAStableNonblankName() {
        let whitespaceBetweenControls = "\u{0007} \u{0007}"
        XCTAssertEqual(NearbyMatch.normalizedName(whitespaceBetweenControls, fallback: ""), "")
        XCTAssertEqual(NearbyMatch.normalizedName(whitespaceBetweenControls), "牌友")
        XCTAssertEqual(NearbyMatch.normalizedName("\u{0007} 哥哥 \u{007F}"), "哥哥")
        XCTAssertEqual(NearbyMatch.normalizedName("\u{2060} \u{200D}", fallback: ""), "")
        XCTAssertEqual(NearbyMatch.normalizedName("\u{0086}\u{2060}"), "牌友")

        let name = NearbyMatch.normalizedName("ABCDEFGHIJK L")
        XCTAssertEqual(name, "ABCDEFGHIJK")
        XCTAssertEqual(NearbyMatch.normalizedName(name), name)

        let family = "👨‍👩‍👧‍👦"
        XCTAssertEqual(NearbyMatch.normalizedName(String(repeating: family, count: 13)),
                       String(repeating: family, count: 12))
    }

    func testNearbySeatReservationAndPrivateSnapshot() throws {
        var host = NearbyMatch(hostName: "阿榕")
        let key = UUID()
        XCTAssertEqual(host.join(key: key, name: "小林"), .south)
        let lobby = host.update(for: .south)
        XCTAssertEqual(lobby.resetsStreakOnPassingDraw, true)
        var oldLobby = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(lobby)) as? [String: Any])
        oldLobby.removeValue(forKey: "resetsStreakOnPassingDraw")
        let oldUpdate = try JSONDecoder().decode(RoomUpdate.self, from: JSONSerialization.data(withJSONObject: oldLobby))
        XCTAssertNil(oldUpdate.resetsStreakOnPassingDraw)
        XCTAssertTrue(host.start())
        let east = try XCTUnwrap(host.update(for: .east).table)
        let south = try XCTUnwrap(host.update(for: .south).table)
        XCTAssertEqual(east.viewer, .east)
        XCTAssertEqual(south.viewer, .south)
        XCTAssertEqual(south.resetsStreakOnPassingDraw, true)
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

    private func fixture(hands: [Seat: [TileKind]], gold: TileKind, draws: [TileKind],
                         ruleset: FuzhouRuleset = .legacy, openingTail: [TileKind] = [],
                         houseRules: FuzhouHouseRules? = nil) throws -> FuzhouMatch {
        var available = Tile.fullSet
        func take(_ kind: TileKind) throws -> Tile {
            let i = try XCTUnwrap(available.firstIndex { $0.kind == kind }, "fixture has too many \(kind)")
            return available.remove(at: i)
        }
        let indicator = try take(gold)
        let drawTiles = try draws.map(take)
        let tail = try openingTail.map(take)
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
        let flipOrder = ruleset == .legacy ? [indicator, available.removeLast()] : [indicator] + tail.reversed()
        let otherReserveCount = 18 - flipOrder.count
        let reserve = Array(available.suffix(otherReserveCount)) + flipOrder
        available.removeLast(otherReserveCount)
        let dealOrder = (0..<16).flatMap { index in Seat.allCases.map { starting[$0]![index] } }
        return FuzhouMatch(deck: available + drawTiles.reversed() + dealOrder.reversed() + reserve,
                           ruleset: ruleset, houseRules: houseRules)
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
