public enum Suit: Int, CaseIterable, Codable, Sendable {
    case characters, circles, bamboo, wind, dragon, flower, season

    public var isBonus: Bool { self == .flower || self == .season }

    var rankCount: Int {
        switch self {
        case .characters, .circles, .bamboo: 9
        case .dragon: 3
        case .wind, .flower, .season: 4
        }
    }
}

public struct TileKind: Hashable, Comparable, Codable, Sendable {
    public let suit: Suit
    public let rank: Int

    public init(_ suit: Suit, _ rank: Int) {
        precondition((1...suit.rankCount).contains(rank))
        self.suit = suit
        self.rank = rank
    }

    public var isFlower: Bool { suit.rawValue > Suit.bamboo.rawValue }

    var suitedIndex: Int? {
        isFlower ? nil : suit.rawValue * 9 + rank - 1
    }

    public func matchesGold(_ indicator: TileKind) -> Bool {
        indicator.suit.isBonus ? suit.isBonus : self == indicator
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.suit.rawValue, lhs.rank) < (rhs.suit.rawValue, rhs.rank)
    }
}

public struct Tile: Hashable, Identifiable, Codable, Sendable {
    public let id: Int
    public let kind: TileKind

    public static let fullSet: [Tile] = {
        var result: [Tile] = []
        for suit in Suit.allCases {
            for rank in 1...suit.rankCount {
                for _ in 0..<(suit.isBonus ? 1 : 4) {
                    result.append(Tile(id: result.count, kind: TileKind(suit, rank)))
                }
            }
        }
        return result
    }()
}
