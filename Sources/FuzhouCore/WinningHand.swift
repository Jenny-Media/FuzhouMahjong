public enum WinningHand {
    public struct Group: Identifiable, Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case pair, sequence, triplet, meld(MeldKind)
        }

        public struct Member: Identifiable, Equatable, Sendable {
            public let tile: Tile
            public let represents: TileKind?
            public var id: Tile.ID { tile.id }
        }

        public let kind: Kind
        public let members: [Member]
        public var id: Tile.ID { members[0].id }
    }

    public static func groups(for result: RoundResult, melds: [Meld], gold: TileKind?) -> [Group]? {
        guard result.winner != nil else { return nil }
        let faceValueFlush = result.pureSuitUsesFaceValues == true
        let joker = result.kind == .robGold || faceValueFlush ? nil : gold
        let flushSuit = result.patterns.contains(.pureSuit)
            ? singleSuit(in: result.winningHand, melds: melds, gold: joker) : nil
        let kinds = result.winningHand.map(\.kind)
        let names = result.lines.map(\.name)
        let sequencesOnly = names.contains(FuzhouScoring.sequenceHandName)
        let goldPair = result.patterns.contains(.goldenPair) || names.contains(FuzhouScoring.goldenPairName) ||
            (sequencesOnly && names.contains(FuzhouScoring.threeGoldName))
        let goldTriplet = names.contains(FuzhouScoring.goldenDragonName)
        var path: [Pattern]? = []
        if solve(kinds, gold: joker, melds: melds.count, sequencesOnly: sequencesOnly,
                 goldPair: goldPair && !faceValueFlush, goldTriplet: goldTriplet,
                 naturalPair: faceValueFlush && goldPair ? gold : nil, path: &path) {
            if goldTriplet { path?.append(Pattern(kind: .triplet, slots: [.gold(nil), .gold(nil), .gold(nil)])) }
        } else {
            // Older settlements can carry scoring labels that do not describe a particular partition.
            path = []
            guard solve(kinds, gold: joker, melds: melds.count, sequencesOnly: false,
                        goldPair: false, goldTriplet: false, path: &path) else { return nil }
        }

        var natural: [Int: [Tile]] = [:]
        var wild: [Tile] = []
        for tile in result.winningHand {
            if let joker, tile.kind.matchesGold(joker) { wild.append(tile) }
            else if let index = tile.kind.suitedIndex { natural[index, default: []].append(tile) }
        }
        var resultGroups: [Group] = []
        for pattern in (path ?? []).reversed() {
            var members: [Group.Member] = []
            for slot in pattern.slots {
                switch slot {
                case .natural(let index):
                    guard let tile = natural[index]?.popLast() else { return nil }
                    members.append(.init(tile: tile, represents: nil))
                case .gold(let index):
                    guard let tile = wild.popLast() else { return nil }
                    let target = index.map { TileKind(Suit.allCases[$0 / 9], $0 % 9 + 1) }
                        ?? flushSuit.map { TileKind($0, tile.kind.rank) }
                    members.append(.init(tile: tile, represents: target == tile.kind ? nil : target))
                }
            }
            resultGroups.append(.init(kind: pattern.kind, members: members))
        }
        resultGroups += melds.map { meld in
            .init(kind: .meld(meld.kind), members: meld.tiles.map { .init(tile: $0, represents: nil) })
        }
        if let winning = result.winningTile,
           let index = resultGroups.firstIndex(where: { $0.members.contains { $0.id == winning.id } }) {
            let completed = resultGroups.remove(at: index)
            resultGroups.insert(completed, at: 0)
        }
        return resultGroups
    }

    static func hasThreeGold(_ tiles: [TileKind], gold: TileKind) -> Bool {
        tiles.count(where: { $0.matchesGold(gold) }) >= 3
    }

    static func singleSuit(in hand: [Tile], melds: [Meld], gold: TileKind?) -> Suit? {
        let natural = hand.filter { tile in gold.map { !tile.kind.matchesGold($0) } ?? true }
        let suits = Set((natural + melds.flatMap(\.tiles)).map(\.kind.suit))
        guard suits.count == 1, let suit = suits.first, suit.rawValue <= Suit.bamboo.rawValue else { return nil }
        return suit
    }

    static func isComplete(_ tiles: [TileKind], gold: TileKind?, melds: Int = 0,
                           sequencesOnly: Bool = false, goldPair: Bool = false,
                           goldTriplet: Bool = false, naturalPair: TileKind? = nil) -> Bool {
        var path: [Pattern]?
        return solve(tiles, gold: gold, melds: melds, sequencesOnly: sequencesOnly,
                     goldPair: goldPair, goldTriplet: goldTriplet, naturalPair: naturalPair, path: &path)
    }

    private struct Pattern {
        enum Slot {
            case natural(Int), gold(Int?)
        }

        let kind: Group.Kind
        let slots: [Slot]

        static func matching(_ kind: Group.Kind, index: Int, natural: Int, total: Int) -> Self {
            Pattern(kind: kind, slots: Array(repeating: .natural(index), count: natural) +
                    Array(repeating: .gold(index), count: total - natural))
        }

        static let goldPair = Pattern(kind: .pair, slots: [.gold(nil), .gold(nil)])
    }

    // A nil path skips reconstruction during normal gameplay and AI searches.
    private static func solve(_ tiles: [TileKind], gold: TileKind?, melds: Int,
                              sequencesOnly: Bool, goldPair: Bool, goldTriplet: Bool,
                              naturalPair: TileKind? = nil, path: inout [Pattern]?) -> Bool {
        guard (0...5).contains(melds), tiles.count == 17 - melds * 3 else { return false }

        var counts = Array(repeating: 0, count: 27)
        var wild = 0
        for tile in tiles {
            if let gold, tile.matchesGold(gold) {
                wild += 1
            } else if let index = tile.suitedIndex {
                counts[index] += 1
            } else {
                return false
            }
        }

        var seen = Set<Position>()
        if goldTriplet {
            guard melds < 5, wild >= 3, !sequencesOnly else { return false }
            wild -= 3
        }
        if let naturalPair {
            guard let index = naturalPair.suitedIndex, counts[index] >= 2 else { return false }
            counts[index] -= 2
            guard findSets(counts, wild: wild, sequencesOnly: sequencesOnly, seen: &seen, path: &path) else { return false }
            path?.append(.matching(.pair, index: index, natural: 2, total: 2))
            return true
        }
        if goldPair {
            guard wild >= 2, findSets(counts, wild: wild - 2, sequencesOnly: sequencesOnly,
                                      seen: &seen, path: &path) else { return false }
            path?.append(.goldPair)
            return true
        }
        // Each suit contributes only complete triples, with the possible pair in one suit.
        let suitTotals = stride(from: 0, to: 27, by: 9).map { counts[$0..<($0 + 9)].reduce(0, +) }
        let requiredWild = suitTotals.indices.map { pairSuit in
            suitTotals.enumerated().reduce(0) { amount, entry in
                amount + ((entry.offset == pairSuit ? 2 : 0) + 3 - entry.element % 3) % 3
            }
        }.min() ?? 0
        guard requiredWild <= wild else { return false }
        for index in counts.indices where counts[index] > 0 {
            for matching in 1...min(counts[index], 2) where wild >= 2 - matching {
                var remainder = counts
                remainder[index] -= matching
                if findSets(remainder, wild: wild - (2 - matching), sequencesOnly: sequencesOnly,
                            seen: &seen, path: &path) {
                    path?.append(.matching(.pair, index: index, natural: matching, total: 2))
                    return true
                }
            }
        }
        guard wild >= 2, findSets(counts, wild: wild - 2, sequencesOnly: sequencesOnly,
                                  seen: &seen, path: &path) else { return false }
        path?.append(.goldPair)
        return true
    }

    private struct Position: Hashable {
        var counts: [Int]
        var wild: Int
    }

    private static func findSets(_ counts: [Int], wild: Int, sequencesOnly: Bool,
                                 seen: inout Set<Position>, path: inout [Pattern]?) -> Bool {
        guard let first = counts.firstIndex(where: { $0 > 0 }) else {
            guard wild.isMultiple(of: 3) else { return false }
            path?.append(contentsOf: Array(repeating: Pattern(kind: sequencesOnly ? .sequence : .triplet,
                                                               slots: [.gold(nil), .gold(nil), .gold(nil)]),
                                           count: wild / 3))
            return true
        }
        guard seen.insert(Position(counts: counts, wild: wild)).inserted else { return false }

        if !sequencesOnly {
            for matching in 1...min(counts[first], 3) where 3 - matching <= wild {
                var remainder = counts
                remainder[first] -= matching
                if findSets(remainder, wild: wild - (3 - matching), sequencesOnly: false,
                            seen: &seen, path: &path) {
                    path?.append(.matching(.triplet, index: first, natural: matching, total: 3))
                    return true
                }
            }
        }

        // A sequence can start below the first remaining tile if a gold fills the lower rank.
        let suitStart = first / 9 * 9
        for start in max(suitStart, first - 2)...min(first, suitStart + 6) {
            let other = (start..<(start + 3)).filter { $0 != first }
            for mask in 0..<4 {
                var remainder = counts
                remainder[first] -= 1
                var missing = 0
                for (offset, index) in other.enumerated() {
                    if (mask & (1 << offset)) == 0, remainder[index] > 0 {
                        remainder[index] -= 1
                    } else {
                        missing += 1
                    }
                }
                if missing <= wild,
                   findSets(remainder, wild: wild - missing, sequencesOnly: sequencesOnly,
                            seen: &seen, path: &path) {
                    path?.append(Pattern(kind: .sequence, slots: (start..<(start + 3)).map { index in
                        counts[index] > remainder[index] ? .natural(index) : .gold(index)
                    }))
                    return true
                }
            }
        }
        return false
    }
}
