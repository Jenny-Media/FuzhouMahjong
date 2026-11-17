enum FuzhouScoring {
    static func lines(hand: [Tile], melds: [Meld], flowers: [Tile], gold: TileKind,
                      dealer: Bool, continuation: Int, openingDraw: Bool, kind: WinKind) -> [RoundResult.Line] {
        var result: [RoundResult.Line] = []
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

        add("基础分", 10)
        add("花牌（\(flowers.count) 张）", flowers.count * 2)
        add("明杠", melds.filter { $0.kind == .openKong || $0.kind == .addedKong }.count * 2)
        add("暗杠", melds.filter { $0.kind == .concealedKong }.count * 2)
        if dealer { add("连庄", continuation * 2) }
        if flowers.count == 1 { add("独花", 15) }

        let flowerKinds = Dictionary(grouping: flowers, by: \.kind)
        let fullBlooms = flowerKinds.values.filter { $0.count == 4 }.count +
            [Suit.flower, .season].filter { suit in
                (1...4).allSatisfy { flowerKinds[TileKind(suit, $0)] != nil }
            }.count
        if fullBlooms > 0 { add("满花（\(fullBlooms) 组）", fullBlooms * 12) }

        // These gold patterns replace the basic gold points. Golden Dragon also replaces all sequences.
        if goldenDragon {
            add("金龙", 40)
        } else {
            if allSequences { add("平胡", 10) }
            if goldCount >= 3 { add("三金倒", 30) }
            else if goldenPair { add("金对", 20) }
            else { add("金牌（\(goldCount) 张）", goldCount * 2) }
        }
        if kind == .robGold {
            add("抢金", 50)
        } else if kind == .selfDraw, openingDraw {
            add(dealer ? "天胡" : "地胡", dealer ? 50 : 40)
        }
        return result
    }
}
