/// Odds for one player's random opening tiles after flowers have been replaced.
public struct FuzhouOpeningOdds: Sendable {
    private let flush: FuzhouHouseRules.Flush
    private let suitedIndicatorChance: Double
    public let windIndicatorChance: Double
    public let dragonIndicatorChance: Double

    public init(flush: FuzhouHouseRules.Flush, goldIndicators: FuzhouHouseRules.GoldIndicators = .suitedOnly) {
        self.flush = flush
        let winds = goldIndicators.includesWinds ? 16.0 : 0.0
        let dragons = goldIndicators.includesDragons ? 12.0 : 0.0
        let eligible = 108 + winds + dragons
        suitedIndicatorChance = 108 / eligible
        windIndicatorChance = winds / eligible
        dragonIndicatorChance = dragons / eligible
    }

    public var atLeastTwoGoldInRack: Double {
        mixed(twoOrMoreGold(from: 107), twoOrMoreGold(from: 111))
    }

    public var threeGoldInRack: Double {
        mixed(threeGold(in: 16, from: 107), threeGold(in: 16, from: 111))
    }

    public func probability(of pattern: WinPattern) -> Double? {
        switch pattern {
        case .robGold:
            // Choosing the suited indicator and then 16 other tiles gives a
            // uniformly random 17-tile set with one tile marked as the indicator.
            suitedIndicatorChance * Counts.robGold / Self.allSuitedRacks
        case .threeGold:
            mixed(threeGold(in: 17, from: 107), threeGold(in: 17, from: 111))
        case .goldenPair:
            mixed((flush == .faceValue ? Counts.faceValuePairSuited : Counts.pairSuited) / Self.suitedGoldRacks,
                  Counts.pairHonor / Self.honorGoldRacks)
        case .pureSuit:
            switch flush {
            case .disabled: nil
            case .wildcard:
                mixed(Counts.wildcardFlushSuited / Self.suitedGoldRacks, Counts.wildcardFlushHonor / Self.honorGoldRacks)
            case .faceValue:
                mixed(Counts.faceValueFlush / Self.allSuitedRacks, Counts.faceValueFlush / Self.honorGoldRacks)
            }
        }
    }

    private func mixed(_ suited: Double, _ honor: Double) -> Double {
        suitedIndicatorChance * suited + (windIndicatorChance + dragonIndicatorChance) * honor
    }

    private func twoOrMoreGold(from total: Double) -> Double {
        // Inclusion-exclusion over the three pairs of physical gold copies.
        3 * (16 / total) * (15 / (total - 1)) - 2 * threeGold(in: 16, from: total)
    }

    private func threeGold(in rack: Double, from total: Double) -> Double {
        (rack / total) * ((rack - 1) / (total - 1)) * ((rack - 2) / (total - 2))
    }

    private static let suitedGoldRacks = 9 * choose17(from: 107)
    private static let honorGoldRacks = choose17(from: 111)
    private static let allSuitedRacks = choose17(from: 108)

    private static func choose17(from total: Int) -> Double {
        (1...17).reduce(1) { count, drawn in count * Double(total - 17 + drawn) / Double(drawn) }
    }

    // Exact physical-tile counts from QA/CountOpeningPatterns.py. Suited gold
    // rank-specific counts are summed over the nine equally likely ranks.
    private enum Counts {
        static let robGold = 880_424_889_312_240.0
        static let pairSuited = 274_095_640_491_196.0
        static let faceValuePairSuited = 274_095_261_828_260.0
        static let pairHonor = 57_471_245_489_316.0
        static let faceValueFlush = 4_780_156_128.0
        static let wildcardFlushSuited = 639_908_280_040.0
        static let wildcardFlushHonor = 102_207_209_496.0
    }
}
