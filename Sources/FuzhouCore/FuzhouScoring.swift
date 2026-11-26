enum FuzhouScoring {
    static let basePoints = 10
    static let pointsPerDealerRepeat = 2
    static let goldenPairName = "金对"
    static let goldenDragonName = "金龙"
    static let threeGoldName = "三金倒"
    static let sequenceHandName = "平胡"

    static func modern(hand: [Tile], melds: [Meld], flowers: [Tile], gold: Tile, dealer: Bool,
                       continuation: Int, kind: WinKind, ruleset: FuzhouRuleset, houseRules: FuzhouHouseRules? = nil)
        -> (lines: [RoundResult.Line], patterns: [WinPattern], faceValueFlush: Bool?) {
        let kinds = hand.map(\.kind)
        let joker = kind == .robGold ? nil : gold.kind
        let goldCount = hand.count(where: { $0.id != gold.id && $0.kind.matchesGold(gold.kind) })
        let flush = houseRules?.flush ?? (ruleset == .pureSuit ? .wildcard : .disabled)
        let flushJoker = flush == .faceValue ? nil : joker
        let isFlush = flush != .disabled && WinningHand.singleSuit(in: hand, melds: melds, gold: flushJoker) != nil &&
            WinningHand.isComplete(kinds, gold: flushJoker, melds: melds.count)
        let faceValueFlush = flush == .faceValue && isFlush
        var patterns: [WinPattern] = []
        if kind == .robGold { patterns.append(.robGold) }
        if kind == .selfDraw, goldCount >= 3 { patterns.append(.threeGold) }
        if joker != nil, goldCount >= 2 {
            // With face-value 清一色, both bonuses must be possible in the same natural grouping.
            let hasGoldPair = faceValueFlush
                ? WinningHand.isComplete(kinds, gold: nil, melds: melds.count, naturalPair: gold.kind)
                : WinningHand.isComplete(kinds, gold: joker, melds: melds.count, goldPair: true)
            if hasGoldPair { patterns.append(.goldenPair) }
        }
        if isFlush { patterns.append(.pureSuit) }

        var lines = baseLines(melds: melds, flowers: flowers, dealer: dealer, continuation: continuation)
        if let bloom = fullBloom(flowers) { lines.append(bloom) }
        if goldCount > 0 { lines.append(.init(name: "金牌（\(goldCount) 张）", points: goldCount * 2)) }
        let bonuses = houseRules?.stackBonuses == true ? patterns : patterns.max(by: { $0.bonus < $1.bonus }).map { [$0] } ?? []
        lines += bonuses.map { .init(name: $0.title, points: $0.bonus) }
        return (lines, patterns, faceValueFlush ? true : nil)
    }

    static func lines(hand: [Tile], melds: [Meld], flowers: [Tile], gold: TileKind,
                      dealer: Bool, continuation: Int, openingDraw: Bool, kind: WinKind) -> [RoundResult.Line] {
        var result = baseLines(melds: melds, flowers: flowers, dealer: dealer, continuation: continuation)
        func add(_ label: String, _ points: Int) {
            if points > 0 { result.append(.init(name: label, points: points)) }
        }

        let tileKinds = hand.map(\.kind)
        let heldTiles = kind == .robGold ? Array(hand.dropLast()) : hand
        let goldInHand = heldTiles.filter { $0.kind.matchesGold(gold) }.count
        let goldCount = goldInHand + flowers.filter { $0.kind.matchesGold(gold) }.count
        let goldenPair = goldInHand >= 2 &&
            WinningHand.isComplete(tileKinds, gold: gold, melds: melds.count, goldPair: true)
        let goldenDragon = goldInHand >= 3 &&
            WinningHand.isComplete(tileKinds, gold: gold, melds: melds.count, goldTriplet: true)
        let allSequences = melds.allSatisfy { $0.kind == .chow } &&
            WinningHand.isComplete(tileKinds, gold: kind == .robGold ? nil : gold, melds: melds.count,
                                   sequencesOnly: true, goldPair: goldCount >= 2)

        if flowers.count == 1 { add("独花", 15) }
        if let bloom = fullBloom(flowers) { result.append(bloom) }

        // These gold patterns replace the basic gold points. Golden Dragon also replaces all sequences.
        if goldenDragon {
            add(goldenDragonName, 40)
        } else {
            if allSequences { add(sequenceHandName, 10) }
            if goldCount >= 3 { add(threeGoldName, 30) }
            else if goldenPair { add(goldenPairName, 20) }
            else { add("金牌（\(goldCount) 张）", goldCount * 2) }
        }
        if kind == .robGold {
            add("抢金", 50)
        } else if kind == .selfDraw, openingDraw {
            add(dealer ? "天胡" : "地胡", dealer ? 50 : 40)
        }
        return result
    }

    private static func baseLines(melds: [Meld], flowers: [Tile], dealer: Bool,
                                  continuation: Int) -> [RoundResult.Line] {
        [
            .init(name: "基础分", points: basePoints),
            .init(name: "花牌（\(flowers.count) 张）", points: flowers.count * 2),
            .init(name: "明杠", points: melds.count(where: { $0.kind == .openKong || $0.kind == .addedKong }) * 2),
            .init(name: "暗杠", points: melds.count(where: { $0.kind == .concealedKong }) * 2),
            .init(name: "连庄", points: dealer ? continuation * pointsPerDealerRepeat : 0),
        ].filter { $0.points > 0 }
    }

    private static func fullBloom(_ flowers: [Tile]) -> RoundResult.Line? {
        let kinds = Dictionary(grouping: flowers, by: \.kind)
        let count = kinds.values.count(where: { $0.count == 4 }) + [Suit.flower, .season].count { suit in
            (1...4).allSatisfy { kinds[TileKind(suit, $0)] != nil }
        }
        return count > 0 ? .init(name: "满花（\(count) 组）", points: count * 12) : nil
    }
}
