public enum WinningHand {
    static func isComplete(_ tiles: [TileKind], gold: TileKind?, melds: Int = 0,
                           sequencesOnly: Bool = false, goldPair: Bool = false,
                           goldTriplet: Bool = false) -> Bool {
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
        if goldPair {
            return wild >= 2 && groups(counts, wild: wild - 2, sequencesOnly: sequencesOnly, seen: &seen)
        }
        for index in counts.indices where counts[index] > 0 {
            for matching in 1...min(counts[index], 2) where wild >= 2 - matching {
                var remainder = counts
                remainder[index] -= matching
                if groups(remainder, wild: wild - (2 - matching), sequencesOnly: sequencesOnly, seen: &seen) {
                    return true
                }
            }
        }
        return wild >= 2 && groups(counts, wild: wild - 2, sequencesOnly: sequencesOnly, seen: &seen)
    }

    private struct Position: Hashable {
        var counts: [Int]
        var wild: Int
    }

    private static func groups(_ counts: [Int], wild: Int, sequencesOnly: Bool, seen: inout Set<Position>) -> Bool {
        guard let first = counts.firstIndex(where: { $0 > 0 }) else { return wild.isMultiple(of: 3) }
        guard seen.insert(Position(counts: counts, wild: wild)).inserted else { return false }

        if !sequencesOnly {
            for matching in 1...min(counts[first], 3) where 3 - matching <= wild {
                var remainder = counts
                remainder[first] -= matching
                if groups(remainder, wild: wild - (3 - matching), sequencesOnly: false, seen: &seen) { return true }
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
                if missing <= wild, groups(remainder, wild: wild - missing, sequencesOnly: sequencesOnly, seen: &seen) {
                    return true
                }
            }
        }
        return false
    }
}
