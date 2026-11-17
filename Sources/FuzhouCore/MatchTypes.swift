public enum Seat: Int, CaseIterable, Codable, Identifiable, Sendable {
    case east, south, west, north

    public var id: Int { rawValue }
    public func advanced(_ count: Int) -> Seat { Seat.allCases[(rawValue + count + 4) % 4] }
}

public enum MeldKind: String, Codable, CaseIterable, Sendable {
    case chow, pung, openKong, concealedKong, addedKong

    var isKong: Bool { self != .chow && self != .pung }
    var priority: Int { self == .chow ? 1 : 2 }
}

public struct Meld: Equatable, Codable, Identifiable, Sendable {
    public var id: Int { tiles[0].id }
    public var kind: MeldKind
    public var tiles: [Tile]
    public var from: Seat?
}

public enum Move: Equatable, Codable, Hashable, Sendable {
    case discard(Int)
    case meld(MeldKind, [Int])
    case replaceFlower(Int)
    case win
    case pass
}

public enum WinKind: String, Codable, Sendable { case selfDraw, discard, robGold }

public struct RoundResult: Equatable, Codable, Sendable {
    public struct Line: Equatable, Codable, Identifiable, Sendable {
        public var id: String { name }
        public var name: String
        public var points: Int
    }

    public var winner: Seat?
    public var kind: WinKind?
    public var source: Seat?
    public var winningTile: Tile?
    public var winningHand: [Tile] = []
    public var lines: [Line]
    public var points: Int { lines.reduce(0) { $0 + $1.points } }

    public func delta(for seat: Seat) -> Int {
        guard let winner else { return 0 }
        if seat == winner { return points * (source == nil ? 3 : 1) }
        return source == nil || source == seat ? -points : 0
    }

    static let draw = Self(winner: nil, kind: nil, source: nil, winningTile: nil, lines: [])
}

public struct TableDiscard: Equatable, Codable, Identifiable, Sendable {
    public var id: Tile.ID { tile.id }
    public let seat: Seat
    public let tile: Tile

    public init(seat: Seat, tile: Tile) {
        self.seat = seat
        self.tile = tile
    }
}

/// Public draw metadata. The drawn tile itself is sent only to its owner.
public struct TableDraw: Equatable, Codable, Sendable {
    public var sequence: Int
    public var seat: Seat
    public var fromReserve: Bool
    public var flowersReplaced: Int
}

public struct TableState: Equatable, Codable, Sendable {
    public struct Player: Equatable, Codable, Identifiable, Sendable {
        public var id: Seat { seat }
        public var seat: Seat
        public var rackCount: Int
        public var flowerCount: Int
        public var discards: [Tile]
        public var melds: [Meld]
        public var score: Int
    }
    public enum Step: String, Codable, Sendable { case opening, turn, claim, finished }

    public var viewer: Seat
    public var hand: [Tile]
    public var drawn: Tile?
    public var gold: Tile?
    public var remaining: Int
    public var dealer: Seat
    public var continuation: Int
    public var roundNumber: Int
    public var wind: Seat
    public var handNumber: Int
    public var matchFinished: Bool
    public var current: Seat
    public var step: Step
    public var offeredTile: Tile?
    public var moves: [Move]
    public var players: [Player]
    public var result: RoundResult?
    public var discardTimeline: [TableDiscard]? = nil
    public var lastDraw: TableDraw? = nil

    public var latestDiscard: TableDiscard? {
        if step == .claim, let offeredTile { return TableDiscard(seat: current, tile: offeredTile) }
        return discardTimeline?.last
    }

    public func isGold(_ tile: Tile) -> Bool { gold.map { tile.kind.matchesGold($0.kind) } ?? false }

    // Gold discards cannot be claimed, so they remain in the player's pond for the hand.
    public var viewerMustSelfDraw: Bool {
        players.first(where: { $0.seat == viewer })?.discards.contains(where: isGold) == true
    }

    public func wind(for seat: Seat) -> Seat { Seat.east.advanced(seat.id - dealer.id) }

    public var isOpeningLayout: Bool {
        result == nil && players.allSatisfy { $0.discards.isEmpty && $0.melds.isEmpty }
    }
}
