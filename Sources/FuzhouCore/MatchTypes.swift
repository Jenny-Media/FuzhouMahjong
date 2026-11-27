import Foundation

public enum Seat: Int, CaseIterable, Codable, Identifiable, Sendable {
    case east, south, west, north

    public var id: Int { rawValue }
    public func advanced(_ count: Int) -> Seat { Seat.allCases[(rawValue + count + 4) % 4] }
}

public enum FuzhouRuleset: String, Codable, Hashable, Sendable {
    case pureSuit, oldThree, legacy

    public static let builtIn: [Self] = [.pureSuit, .oldThree]
}

public struct FuzhouHouseRules: Codable, Hashable, Identifiable, Sendable {
    public enum DiscardPayment: String, CaseIterable, Codable, Sendable {
        case discarder, allOpponents
    }

    public enum Flush: String, CaseIterable, Codable, Sendable {
        case disabled, wildcard, faceValue
    }

    public enum GoldIndicators: String, CaseIterable, Codable, Sendable {
        case suitedOnly, includeWinds, includeDragons, includeHonors

        public var includesWinds: Bool { self == .includeWinds || self == .includeHonors }
        public var includesDragons: Bool { self == .includeDragons || self == .includeHonors }

        public var revealsBeforeFlowers: Bool { self != .suitedOnly }

        public func allows(_ kind: TileKind) -> Bool {
            switch kind.suit {
            case .wind: includesWinds
            case .dragon: includesDragons
            case .flower, .season: false
            default: true
            }
        }
    }

    public let id: UUID
    public var name: String
    public var keepDealerOnDraw: Bool
    public var discardPayment: DiscardPayment
    public var flush: Flush
    public var stackBonuses: Bool
    private var additionalGoldIndicators: GoldIndicators?

    public var goldIndicators: GoldIndicators {
        get { additionalGoldIndicators ?? .suitedOnly }
        set { additionalGoldIndicators = newValue == .suitedOnly ? nil : newValue }
    }

    public init(name: String, keepDealerOnDraw: Bool = false, discardPayment: DiscardPayment = .discarder,
                flush: Flush = .wildcard, stackBonuses: Bool = false, goldIndicators: GoldIndicators = .suitedOnly) {
        id = UUID()
        self.name = name
        self.keepDealerOnDraw = keepDealerOnDraw
        self.discardPayment = discardPayment
        self.flush = flush
        self.stackBonuses = stackBonuses
        self.goldIndicators = goldIndicators
    }

    var baseRuleset: FuzhouRuleset { flush == .disabled ? .oldThree : .pureSuit }
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

public enum DiscardClaimFeedback: Equatable, Codable, Sendable {
    case pending(Move)
    case overridden(Move, by: Move)
}

public enum WinKind: String, Codable, Sendable { case selfDraw, discard, robGold }

public enum WinPattern: String, Codable, Identifiable, Sendable {
    case robGold, threeGold, goldenPair, pureSuit

    public var id: Self { self }

    public var title: String {
        switch self {
        case .robGold: "抢金"
        case .threeGold: "三金倒"
        case .goldenPair: "金雀（金对）"
        case .pureSuit: "清一色"
        }
    }

    public var bonus: Int {
        switch self {
        case .robGold: 30
        case .threeGold: 40
        case .goldenPair: 60
        case .pureSuit: 240
        }
    }
}

public struct RoundResult: Equatable, Codable, Sendable {
    public struct Line: Equatable, Codable, Identifiable, Sendable {
        public var id: String { name }
        public var name: String
        public var points: Int
    }

    public var winner: Seat?
    public var kind: WinKind?
    /// The sole payer, when the settlement charges one player.
    public var source: Seat?
    public var winningTile: Tile?
    public var winningHand: [Tile] = []
    public var lines: [Line]
    var matchedPatterns: [WinPattern]? = nil
    var pureSuitUsesFaceValues: Bool? = nil
    public var patterns: [WinPattern] { matchedPatterns ?? [] }
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
    /// True for the dealer's extra tile dealt before the gold reveal.
    public var isOpeningDeal: Bool? = nil
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
        /// Flowers already shown at this seat. Older hosts supply only the count.
        public var exposedFlowers: [Tile]? = nil
        /// Positions of concealed kongs whose tiles are withheld from this viewer.
        public var concealedKongPositions: [Int]? = nil

        public var meldCount: Int { melds.count + (concealedKongPositions?.count ?? 0) }
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
    /// Final concealed tiles by seat, available only for a finished hand with review enabled.
    public var settledHands: [Seat: [Tile]]? = nil
    /// Human seat names at settlement, retained while the finished hand is available.
    public var settledPlayerNames: [Seat: String]? = nil
    /// Set by hosts that count a player's separate draw in Player.rackCount.
    public var rackCountsIncludeDrawnTile: Bool? = nil
    public var discardTimeline: [TableDiscard]? = nil
    public var lastDraw: TableDraw? = nil
    var matchRuleset: FuzhouRuleset? = nil
    public var houseRules: FuzhouHouseRules? = nil
    /// The dealer may trade one of these tiles for the flipped indicator when declaring 抢金.
    public var robGoldDiscardIDs: [Tile.ID]? = nil
    /// Only the table viewer's own discard claim is reported here.
    public var discardClaimFeedback: DiscardClaimFeedback? = nil
    /// Public flowers the dealer collected while flipping for gold, in reveal order.
    public var openingIndicatorFlowerIDs: [Tile.ID]? = nil
    /// Absent on older tables that added to the streak on a draw, even when the deal passed.
    public var resetsStreakOnPassingDraw: Bool? = nil

    public var ruleset: FuzhouRuleset { matchRuleset ?? .legacy }

    /// A nil entry represents four face-down tiles, including when an older host sent their faces.
    public func displayedMelds(for player: Player) -> [Meld?] {
        var melds: [Meld?] = player.melds.map { meld in
            step != .finished && player.seat != viewer && meld.kind == .concealedKong ? nil : meld
        }
        for position in player.concealedKongPositions ?? [] where (0...melds.count).contains(position) {
            melds.insert(nil, at: position)
        }
        return melds
    }

    /// Identifies a move while treating the settlement reveal as a change in visibility.
    public func meldChange(since before: Self) -> (seat: Seat, kind: MeldKind, meld: Meld?)? {
        guard roundNumber == before.roundNumber, viewer == before.viewer else { return nil }
        for (old, new) in zip(before.players, players) {
            if let meld = new.melds.first(where: {
                (new.seat == viewer || $0.kind != .concealedKong) && !old.melds.contains($0)
            }) {
                return (new.seat, meld.kind, meld)
            }
            if new.meldCount > old.meldCount {
                return (new.seat, .concealedKong, nil)
            }
        }
        return nil
    }

    public func concealedCount(for player: Player) -> Int {
        if rackCountsIncludeDrawnTile == true { return player.rackCount }
        if player.seat == viewer { return hand.count + (drawn == nil ? 0 : 1) }
        // Both older formats used protocol v1. Some included the draw, others sent only the rack.
        // A chow or pung already leaves an extra tile in the rack before the claimant discards.
        guard player.seat == current, player.rackCount == FuzhouMatch.rackSize - 3 * player.meldCount else {
            return player.rackCount
        }
        let dealerHoldsExtra = player.seat == dealer && lastDraw?.isOpeningDeal == true
        switch step {
        case .turn: return player.rackCount + 1
        case .opening where dealerHoldsExtra: return player.rackCount + 1
        case .finished where dealerHoldsExtra && result?.kind == .robGold && result?.winner != dealer:
            return player.rackCount + 1
        default: return player.rackCount
        }
    }

    public func canSubmit(_ move: Move) -> Bool {
        if moves.contains(move) { return true }
        guard step == .opening, viewer == dealer, moves.contains(.win), case .discard(let id) = move else { return false }
        return robGoldDiscardIDs?.contains(id) == true
    }

    public var canDeclareThreeGold: Bool {
        guard ruleset != .legacy, step == .turn, let drawn, let gold else { return false }
        return WinningHand.hasThreeGold((hand + [drawn]).map(\.kind), gold: gold.kind)
    }

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
        result == nil && players.allSatisfy { $0.discards.isEmpty && $0.meldCount == 0 }
    }
}
