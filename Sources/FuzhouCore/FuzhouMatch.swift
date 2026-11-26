public struct FuzhouMatch: Equatable, Codable, Sendable {
    public static let rackSize = 16
    public static let player = Seat.south
    private static let scheduledHands = 16
    private static let tileCopies = Dictionary(grouping: Tile.fullSet, by: \.kind).mapValues(\.count)

    private enum Response: Equatable, Codable, Sendable {
        case pending(Seat)
        case chose(Seat, Move)

        var seat: Seat {
            switch self { case .pending(let seat), .chose(let seat, _): seat }
        }
    }

    private var wall: [Tile] = []
    private var reserve: [Tile] = []
    private var hands = Array(repeating: [Tile](), count: 4)
    private var flowers = Array(repeating: [Tile](), count: 4)
    private var openingIndicatorFlowerIDs: [Tile.ID]?
    private var ponds = Array(repeating: [Tile](), count: 4)
    private var discardTimeline: [TableDiscard]?
    private var lastDraw: TableDraw?
    private var melds = Array(repeating: [Meld](), count: 4)
    private var selfDrawOnly = Set<Seat>()
    private var drew = Set<Seat>()
    private var firstDraw = false
    private var responses: [Response] = []
    private var overriddenClaims: [Seat: DiscardClaimFeedback]?
    private var openingDealerGoldDiscards: [Tile.ID]?
    private var step = TableState.Step.turn
    private var offeredTile: Tile?
    private var matchRuleset: FuzhouRuleset?

    public private(set) var gold: Tile?
    public private(set) var current = Seat.east
    public private(set) var dealer = Seat.east
    public private(set) var drawn: Tile?
    public private(set) var result: RoundResult?
    public private(set) var scores = Array(repeating: 0, count: 4)
    public private(set) var roundNumber = 1
    public private(set) var dealerTurns = 0
    public private(set) var continuation = 0
    public private(set) var houseRules: FuzhouHouseRules?
    public var ruleset: FuzhouRuleset { matchRuleset ?? .legacy }

    public var matchFinished: Bool {
        dealerTurns == Self.scheduledHands - 1 && result.map { !repeatsDealer(after: $0) } == true
    }

    public init(ruleset: FuzhouRuleset = .pureSuit, houseRules: FuzhouHouseRules? = nil) {
        var random = SystemRandomNumberGenerator()
        self.init(using: &random, ruleset: ruleset, houseRules: houseRules)
    }

    public init<R: RandomNumberGenerator>(using random: inout R, ruleset: FuzhouRuleset = .pureSuit,
                                          houseRules: FuzhouHouseRules? = nil) {
        self.init(deck: Tile.fullSet.shuffled(using: &random), ruleset: ruleset, houseRules: houseRules)
    }

    init(deck: [Tile], ruleset: FuzhouRuleset = .pureSuit, houseRules: FuzhouHouseRules? = nil) {
        self.houseRules = houseRules
        let base = houseRules?.baseRuleset ?? ruleset
        matchRuleset = base == .legacy ? nil : base
        deal(deck)
    }

    public func table(for viewer: Seat) -> TableState {
        let moves = legalMoves(for: viewer)
        let openingDiscards = step == .opening && viewer == dealer && moves.contains(.win) ? openingDealerGoldDiscards : nil
        let claimFeedback: DiscardClaimFeedback?
        if step == .claim, case let .chose(_, move)? = responses.first(where: { $0.seat == viewer }), move != .pass {
            claimFeedback = .pending(move)
        } else {
            claimFeedback = overriddenClaims?[viewer]
        }
        return TableState(viewer: viewer, hand: hands[viewer.id], drawn: current == viewer ? drawn : nil,
                   gold: gold, remaining: wall.count, dealer: dealer, continuation: continuation,
                   roundNumber: roundNumber, wind: Seat.allCases[dealerTurns / 4],
                   handNumber: dealerTurns % 4 + 1, matchFinished: matchFinished, current: current,
                   step: step, offeredTile: offeredTile, moves: openingDiscards == nil ? moves : [.win, .pass],
                   players: Seat.allCases.map {
                       let count = hands[$0.id].count + ($0 == current && drawn != nil ? 1 : 0)
                       return .init(seat: $0, rackCount: count, flowerCount: flowers[$0.id].count,
                                    discards: ponds[$0.id], melds: melds[$0.id], score: scores[$0.id],
                                    exposedFlowers: flowers[$0.id])
                   }, result: result, rackCountsIncludeDrawnTile: true, discardTimeline: discardTimeline, lastDraw: lastDraw,
                   matchRuleset: matchRuleset, houseRules: houseRules, robGoldDiscardIDs: openingDiscards,
                   discardClaimFeedback: claimFeedback, openingIndicatorFlowerIDs: openingIndicatorFlowerIDs)
    }

    public func legalMoves(for seat: Seat) -> [Move] {
        switch step {
        case .finished:
            return []
        case .opening:
            guard responses.contains(.pending(seat)) else { return [] }
            return [.win, .pass] + (seat == dealer ? (openingDealerGoldDiscards ?? []).map(Move.discard) : [])
        case .claim:
            guard responses.contains(.pending(seat)), let offeredTile else { return [] }
            return discardClaims(for: seat, tile: offeredTile) + [.pass]
        case .turn:
            guard seat == current else { return [] }
            let rack = combinedHand(for: seat)
            var moves = rack.filter(canDiscard).map { Move.discard($0.id) }
            if ruleset == .legacy, !reserve.isEmpty {
                moves += rack.filter { $0.kind.isFlower && isGold($0) }.map { Move.replaceFlower($0.id) }
            }
            if drawn != nil, canSelfDrawWin(rack.map(\.kind), meldCount: melds[seat.id].count) { moves.insert(.win, at: 0) }
            if drawn != nil, !wall.isEmpty, !reserve.isEmpty {
                let groups = Dictionary(grouping: rack.filter { !$0.kind.isFlower && !isGold($0) }, by: \.kind)
                if melds[seat.id].count < 5 {
                    moves += groups.keys.sorted().compactMap { kind in
                        guard let tiles = groups[kind], tiles.count == 4 else { return nil }
                        return .meld(.concealedKong, tiles.map(\.id).sorted())
                    }
                }
                for meld in melds[seat.id] where meld.kind == .pung {
                    if let tile = groups[meld.tiles[0].kind]?.first {
                        moves.append(.meld(.addedKong, [tile.id]))
                    }
                }
            }
            return moves
        }
    }

    @discardableResult
    public mutating func apply(_ move: Move, by seat: Seat) -> Bool {
        guard legalMoves(for: seat).contains(move) else { return false }
        switch step {
        case .opening, .claim:
            let index = responses.firstIndex(of: .pending(seat))!
            responses[index] = .chose(seat, move)
            resolveResponses()
        case .turn:
            switch move {
            case .discard(let id):
                discard(id, by: seat)
            case .win:
                if let drawn { finishWin(seat, kind: .selfDraw, tile: drawn, source: nil) }
            case .meld(let kind, let ids):
                selfKong(kind, ids: ids, by: seat)
            case .replaceFlower(let id):
                gatherDrawn(for: seat)
                flowers[seat.id].append(removeTiles([id], from: seat)[0])
                sortHand(seat)
                drawTurn(fromReserve: true)
            case .pass: return false
            }
        case .finished:
            return false
        }
        return true
    }

    /// Settles a restored discard window when all remaining claims are already outranked.
    public mutating func settleRestoredDiscard() -> Bool {
        guard step == .claim else { return false }
        resolveResponses()
        return step != .claim
    }

    /// Older saves could carry a streak across a draw that changed the dealer.
    /// Use completed hands and known winners to rule out unearned repeats.
    private var boundedDealerStreak: Int {
        guard continuation > 0, dealerTurns > 0, houseRules?.keepDealerOnDraw != true else { return continuation }
        let priorHands = max(1, roundNumber) - 1
        let dealerWins = max(0, priorHands - dealerTurns)
        // A non-dealer win reset the streak even in the old format. Any such win
        // preceded the saved streak and used up one change of dealer.
        let possibleNonDealerWins = min(dealerTurns, max(0, priorHands - continuation))
        let otherWinners = Seat.allCases.count { seat in
            // A positive balance before this hand proves the seat won at least once.
            seat != dealer && scores[seat.id] > (result?.delta(for: seat) ?? 0)
        }
        let otherDealerWins = max(0, otherWinners - possibleNonDealerWins)
        return min(continuation, max(0, dealerWins - otherDealerWins))
    }

    public mutating func reconcileSavedHand() -> Bool {
        let previous = continuation
        if result == nil { continuation = boundedDealerStreak }
        let settled = settleRestoredDiscard()
        return settled || previous != continuation
    }

    public func hasComputerMove(excluding humans: Set<Seat>) -> Bool {
        switch step {
        case .finished: false
        case .turn: !humans.contains(current) && !legalMoves(for: current).isEmpty
        case .claim, .opening:
            responses.contains {
                if case .pending(let seat) = $0 { return !humans.contains(seat) }
                return false
            }
        }
    }

    public func nextComputerMove(excluding humans: Set<Seat>) -> (Seat, Move)? {
        if step == .finished { return nil }
        let candidates = step == .turn ? [current] : responses.map(\.seat)
        for seat in candidates where !humans.contains(seat) {
            let moves = legalMoves(for: seat)
            if moves.contains(.win) { return (seat, .win) }
            if let kong = moves.first(where: {
                if case .meld(let kind, _) = $0 { kind.isKong } else { false }
            }) {
                return (seat, kong)
            }
            let tiles = combinedHand(for: seat)
            if moves.contains(.pass) {
                if let claim = preferredClaim(moves, seat: seat, tiles: tiles) { return (seat, claim) }
                return (seat, .pass)
            }
            let discardable = Set(moves.compactMap { if case .discard(let id) = $0 { id } else { nil } })
            if !discardable.isEmpty, let best = bestDiscard(from: tiles, allowed: discardable,
                                                           meldCount: melds[seat.id].count,
                                                           available: availableDraws(seenBy: seat)) {
                return (seat, .discard(best.tile.id))
            }
            if let fallback = moves.first { return (seat, fallback) }
        }
        return nil
    }

    private func preferredClaim(_ moves: [Move], seat: Seat, tiles: [Tile]) -> Move? {
        guard moves.contains(where: { if case .meld = $0 { true } else { false } }) else { return nil }
        let available = availableDraws(seenBy: seat)
        let count = melds[seat.id].count
        var bestWaits = winningCopies(tiles, meldCount: count, available: available)
        var chosen: Move?
        for move in moves {
            guard case let .meld(kind, ids) = move, kind == .pung || kind == .chow else { continue }
            let rest = tiles.filter { !ids.contains($0.id) }
            let allowed = Set(rest.filter(canDiscard).map(\.id))
            guard let followUp = bestDiscard(from: rest, allowed: allowed, meldCount: count + 1,
                                             available: available) else { continue }
            // Prefer a pung on an equal wait; a chow must improve on passing.
            if followUp.waits > bestWaits || (kind == .pung && followUp.waits == bestWaits) {
                bestWaits = followUp.waits
                chosen = move
            }
        }
        return chosen
    }

    private func bestDiscard(from tiles: [Tile], allowed: Set<Tile.ID>, meldCount: Int,
                             available: [TileKind: Int]) -> (tile: Tile, waits: Int)? {
        let legal = tiles.filter { allowed.contains($0.id) }
        let ordinary = legal.filter { !isGold($0) }
        var seen = Set<TileKind>()
        var best: (tile: Tile, waits: Int, connections: Int)?
        for tile in (ordinary.isEmpty ? legal : ordinary).sorted(by: { $0.id < $1.id })
        where seen.insert(tile.kind).inserted {
            let rest = tiles.filter { $0.id != tile.id }
            let waits = winningCopies(rest, meldCount: meldCount, available: available)
            let connections = utility(tile, in: tiles)
            if let best, (best.waits, -best.connections) >= (waits, -connections) { continue }
            best = (tile, waits, connections)
        }
        return best.map { ($0.tile, $0.waits) }
    }

    private func availableDraws(seenBy seat: Seat) -> [TileKind: Int] {
        let indicator = gold?.kind
        var copies = Self.tileCopies
        let visible = combinedHand(for: seat) + ponds.flatMap { $0 }
            + melds.flatMap { $0 }.flatMap(\.tiles) + flowers[seat.id] + [gold].compactMap { $0 }
        for tile in Set(visible) { copies[tile.kind, default: 0] -= 1 }
        var suited: [TileKind: Int] = [:]
        for (kind, count) in copies where count > 0 {
            if let indicator, kind.matchesGold(indicator) {
                suited[indicator, default: 0] += count
            } else if !kind.isFlower {
                suited[kind] = count
            }
        }
        return suited
    }

    private func winningCopies(_ tiles: [Tile], meldCount: Int, available: [TileKind: Int]) -> Int {
        let hand = tiles.map(\.kind)
        return available.reduce(0) { total, entry in
            total + (canSelfDrawWin(hand + [entry.key], meldCount: meldCount) ? entry.value : 0)
        }
    }

    public mutating func nextRound() {
        guard let result else { return }
        if matchFinished {
            self = FuzhouMatch(ruleset: ruleset, houseRules: houseRules)
            return
        }
        if repeatsDealer(after: result) {
            continuation = boundedDealerStreak + 1
        } else {
            dealer = dealer.advanced(1)
            dealerTurns += 1
            continuation = 0
        }
        roundNumber += 1
        var random = SystemRandomNumberGenerator()
        deal(Tile.fullSet.shuffled(using: &random))
    }

    private func repeatsDealer(after result: RoundResult) -> Bool {
        result.winner == dealer || (result.winner == nil && houseRules?.keepDealerOnDraw == true)
    }

    private mutating func deal(_ deck: [Tile]) {
        wall = Array(deck.dropLast(18))
        reserve = Array(deck.suffix(18))
        hands = Array(repeating: [], count: 4)
        flowers = Array(repeating: [], count: 4)
        resetHandState()
        current = dealer
        gold = nil
        drawn = nil
        result = nil
        step = .opening

        for _ in 0..<Self.rackSize {
            for offset in 0..<4 {
                let seat = dealer.advanced(offset)
                guard let tile = wall.popLast() else { settle(.draw); return }
                hands[seat.id].append(tile)
            }
        }
        let hasDealerExtra = ruleset != .legacy
        if hasDealerExtra {
            guard let extra = wall.popLast() else { settle(.draw); return }
            hands[dealer.id].append(extra)
        }
        // Reveal before replacing flowers when honors can be gold, so dealt copies of the
        // indicator stay in players' racks instead of being counted as flowers.
        if goldIndicators.revealsBeforeFlowers {
            guard let indicator = revealGold() else { settle(.draw); return }
            gold = indicator
        }
        guard let extraFlowers = replaceOpeningFlowers(),
              let indicator = gold ?? revealGold() else { settle(.draw); return }
        gold = indicator
        if hasDealerExtra {
            let ready = hands[dealer.id].removeLast()
            drawn = ready
            drew.insert(dealer)
            firstDraw = true
            lastDraw = TableDraw(sequence: 1, seat: dealer, fromReserve: extraFlowers > 0,
                                 flowersReplaced: extraFlowers, isOpeningDeal: true)
        }
        for seat in Seat.allCases { sortHand(seat) }
        if let drawn {
            let discards = dealerGoldDiscards(drawn: drawn, indicator: indicator)
            openingDealerGoldDiscards = discards.isEmpty ? nil : discards
        }
        // The reveal must complete the original hand as a tile, before gold begins acting as a joker.
        responses = (0..<4).map { dealer.advanced($0) }.filter { seat in
            if seat == dealer, drawn != nil { return openingDealerGoldDiscards != nil }
            return WinningHand.isComplete((hands[seat.id] + [indicator]).map(\.kind), gold: nil)
        }.map(Response.pending)
        if responses.isEmpty { beginFirstTurn() }
    }

    private func dealerGoldDiscards(drawn: Tile, indicator: Tile) -> [Tile.ID] {
        guard !indicator.kind.isFlower else { return [] }
        let rack = hands[dealer.id] + [drawn]
        let choices: [(tile: Tile, points: Int)] = rack.compactMap { tile in
            let hand = rack.filter { $0.id != tile.id } + [indicator]
            guard WinningHand.isComplete(hand.map(\.kind), gold: nil) else { return nil }
            let score = FuzhouScoring.modern(hand: hand, melds: [], flowers: flowers[dealer.id],
                                             gold: indicator, dealer: true, continuation: continuation,
                                             kind: .robGold, ruleset: ruleset, houseRules: houseRules)
            return (tile, score.lines.reduce(0) { $0 + $1.points })
        }
        // A plain win request from AI or an older client picks the highest-scoring swap.
        return choices.sorted {
            ($0.points, $0.tile == drawn ? 1 : 0, -$0.tile.id) > ($1.points, $1.tile == drawn ? 1 : 0, -$1.tile.id)
        }.map(\.tile.id)
    }

    private mutating func beginFirstTurn() {
        // Older saves awaiting an opening response still need to draw the dealer's extra tile.
        if drawn == nil { drawTurn() }
        else { step = .turn }
    }

    private mutating func replaceOpeningFlowers() -> Int? {
        let seats = (0..<4).map { dealer.advanced($0) }
        var dealerExtraFlowers = 0
        if ruleset == .legacy {
            for seat in seats {
                let dealt = hands[seat.id]
                hands[seat.id] = []
                for tile in dealt {
                    guard let ready = replaceFlowers(tile, for: seat) else { return nil }
                    hands[seat.id].append(ready)
                }
            }
        } else {
            // Flowers drawn as replacements wait until the player's next pass around the table.
            while hands.contains(where: { $0.contains(where: needsFlowerReplacement) }) {
                for seat in seats {
                    for index in hands[seat.id].indices where needsFlowerReplacement(hands[seat.id][index]) {
                        guard let tile = replacement() else { return nil }
                        flowers[seat.id].append(hands[seat.id][index])
                        hands[seat.id][index] = tile
                        if seat == dealer, index == Self.rackSize { dealerExtraFlowers += 1 }
                    }
                }
            }
        }
        return dealerExtraFlowers
    }

    private mutating func revealGold() -> Tile? {
        if ruleset == .legacy {
            guard reserve.count >= 2 else { return nil }
            return reserve.remove(at: reserve.count - 2)
        }
        while let tile = reserve.last, !goldIndicators.allows(tile.kind) {
            guard let flower = replacement() else { return nil }
            flowers[dealer.id].append(flower)
            openingIndicatorFlowerIDs?.append(flower.id)
        }
        return reserve.popLast()
    }

    private mutating func resetHandState() {
        openingIndicatorFlowerIDs = []
        ponds = Array(repeating: [], count: 4)
        discardTimeline = []
        lastDraw = nil
        melds = Array(repeating: [], count: 4)
        selfDrawOnly = []
        drew = []
        firstDraw = false
        responses = []
        overriddenClaims = nil
        openingDealerGoldDiscards = nil
        offeredTile = nil
    }

    private var goldIndicators: FuzhouHouseRules.GoldIndicators { houseRules?.goldIndicators ?? .suitedOnly }

    private func isGold(_ tile: Tile) -> Bool { gold.map { tile.kind.matchesGold($0.kind) } ?? false }

    private func needsFlowerReplacement(_ tile: Tile) -> Bool { tile.kind.isFlower && !isGold(tile) }

    private func canDiscard(_ tile: Tile) -> Bool { !tile.kind.isFlower || (ruleset != .legacy && isGold(tile)) }

    private func combinedHand(for seat: Seat) -> [Tile] {
        hands[seat.id] + (seat == current ? [drawn].compactMap { $0 } : [])
    }

    private func canWin(_ seat: Seat, tiles: [Tile]) -> Bool {
        WinningHand.isComplete(tiles.map(\.kind), gold: gold?.kind, melds: melds[seat.id].count)
    }

    private func canSelfDrawWin(_ tiles: [TileKind], meldCount: Int) -> Bool {
        if ruleset != .legacy, let gold, WinningHand.hasThreeGold(tiles, gold: gold.kind) { return true }
        return WinningHand.isComplete(tiles, gold: gold?.kind, melds: meldCount)
    }

    private func discardClaims(for seat: Seat, tile: Tile) -> [Move] {
        guard !isGold(tile), !tile.kind.isFlower else { return [] }
        var moves: [Move] = []
        if !selfDrawOnly.contains(seat), canWin(seat, tiles: hands[seat.id] + [tile]) {
            moves.append(.win)
        }
        guard !wall.isEmpty, melds[seat.id].count < 5 else { return moves }
        let usable = hands[seat.id].filter { !$0.kind.isFlower && !isGold($0) }
        let matches = usable.filter { $0.kind == tile.kind }.map(\.id).sorted()
        if matches.count >= 2 { moves.append(.meld(.pung, Array(matches.prefix(2)))) }
        if matches.count >= 3, !wall.isEmpty, !reserve.isEmpty {
            moves.append(.meld(.openKong, Array(matches.prefix(3))))
        }
        if seat == current.advanced(1) {
            let rank = tile.kind.rank
            for start in max(1, rank - 2)...min(rank, 7) {
                let others = (start..<(start + 3)).filter { $0 != rank }
                let need = others.compactMap { wanted in
                    usable.first { $0.kind.suit == tile.kind.suit && $0.kind.rank == wanted }?.id
                }
                if need.count == 2 { moves.append(.meld(.chow, need.sorted())) }
            }
        }
        return moves
    }

    private mutating func discard(_ id: Int, by seat: Seat) {
        let tile = recordDiscard(id, by: seat)
        firstDraw = false
        overriddenClaims = nil
        offeredTile = tile
        step = .claim
        responses = (1..<4).map { seat.advanced($0) }.filter {
            !discardClaims(for: $0, tile: tile).isEmpty
        }.map(Response.pending)
        if responses.isEmpty { resolveResponses() }
    }

    @discardableResult
    private mutating func recordDiscard(_ id: Tile.ID, by seat: Seat) -> Tile {
        gatherDrawn(for: seat)
        let tile = removeTiles([id], from: seat)[0]
        sortHand(seat)
        if isGold(tile) { selfDrawOnly.insert(seat) }
        ponds[seat.id].append(tile)
        if discardTimeline == nil { discardTimeline = [] }
        discardTimeline?.append(TableDiscard(seat: seat, tile: tile))
        return tile
    }

    private mutating func resolveResponses() {
        if step == .opening {
            guard !responses.contains(where: { if case .pending = $0 { true } else { false } }) else { return }
            let choice = responses.first { if case .chose(_, .pass) = $0 { false } else { true } }
            responses = []
            let defaultDiscard = openingDealerGoldDiscards?.first
            openingDealerGoldDiscards = nil
            if case let .chose(winner, move)? = choice, let gold {
                if winner == dealer {
                    if case .discard(let id) = move { recordDiscard(id, by: dealer) }
                    else if let defaultDiscard { recordDiscard(defaultDiscard, by: dealer) }
                }
                finishWin(winner, kind: .robGold, tile: gold, source: nil)
            } else {
                beginFirstTurn()
            }
            return
        }

        guard let tile = offeredTile else { return }
        // Rank each pending player by their best possible claim. The response order breaks ties.
        let leader = responses.enumerated().compactMap { index, response -> (rank: Int, order: Int, response: Response)? in
            switch response {
            case .pending(let seat):
                let best = discardClaims(for: seat, tile: tile).map { priority($0, by: seat, claiming: tile) }.max()
                return best.map { ($0, -index, response) }
            case .chose(let seat, let move):
                return move == .pass ? nil : (priority(move, by: seat, claiming: tile), -index, response)
            }
        }.max { ($0.rank, $0.order) < ($1.rank, $1.order) }?.response
        if case .pending? = leader { return }

        let source = current
        let resolvedResponses = responses
        responses = []
        defer { offeredTile = nil }
        if case let .chose(seat, move)? = leader {
            let overridden = resolvedResponses.compactMap { response -> (Seat, DiscardClaimFeedback)? in
                guard case let .chose(other, attempted) = response, other != seat, attempted != .pass else { return nil }
                return (other, .overridden(attempted, by: move))
            }
            if !overridden.isEmpty { overriddenClaims = Dictionary(uniqueKeysWithValues: overridden) }
            switch move {
            case .win:
                finishWin(seat, kind: .discard, tile: tile, source: source)
                return
            case .meld(let kind, let ids):
                ponds[source.id].removeLast()
                let taken = removeTiles(ids, from: seat)
                melds[seat.id].append(Meld(kind: kind, tiles: (taken + [tile]).sorted { $0.kind < $1.kind }, from: source))
                current = seat
                firstDraw = false
                step = .turn
                if kind.isKong { drawTurn(fromReserve: true, allowOpeningBonus: false) }
                return
            default: break
            }
        }
        current = source.advanced(1)
        drawTurn()
    }

    private func priority(_ move: Move, by seat: Seat, claiming tile: Tile) -> Int {
        switch move {
        case .win:
            if ruleset != .legacy, WinningHand.isComplete((hands[seat.id] + [tile]).map(\.kind), gold: gold?.kind,
                                                         melds: melds[seat.id].count, goldPair: true) { return 4 }
            return 3
        case .meld(let kind, _): return kind.priority
        default: return 0
        }
    }

    private mutating func selfKong(_ kind: MeldKind, ids: [Int], by seat: Seat) {
        gatherDrawn(for: seat)
        let tiles = removeTiles(ids, from: seat)
        if kind == .addedKong, let tile = tiles.first,
           let index = melds[seat.id].firstIndex(where: { $0.kind == .pung && $0.tiles[0].kind == tile.kind }) {
            melds[seat.id][index].kind = .addedKong
            melds[seat.id][index].tiles += tiles
        } else {
            melds[seat.id].append(Meld(kind: kind, tiles: tiles, from: nil))
        }
        sortHand(seat)
        if kind == .concealedKong, !wall.isEmpty { reserve.insert(wall.removeFirst(), at: 0) }
        drawTurn(fromReserve: true, allowOpeningBonus: false)
    }

    private mutating func removeTiles(_ ids: [Int], from seat: Seat) -> [Tile] {
        let chosen = Set(ids)
        let tiles = hands[seat.id].filter { chosen.contains($0.id) }
        hands[seat.id].removeAll { chosen.contains($0.id) }
        return tiles
    }

    private mutating func drawTurn(fromReserve: Bool = false, allowOpeningBonus: Bool = true) {
        let existingFlowers = flowers[current.id].count
        let tile = fromReserve ? replacement() : wall.popLast()
        guard let tile, let ready = replaceFlowers(tile, for: current) else { settle(.draw); return }
        if !fromReserve { firstDraw = drew.insert(current).inserted && melds.allSatisfy(\.isEmpty) }
        else if !allowOpeningBonus { firstDraw = false }
        drawn = ready
        lastDraw = TableDraw(sequence: (lastDraw?.sequence ?? 0) + 1, seat: current,
                             fromReserve: fromReserve, flowersReplaced: flowers[current.id].count - existingFlowers)
        step = .turn
    }

    private mutating func replacement() -> Tile? {
        guard let tile = reserve.popLast() else { return nil }
        if !wall.isEmpty { reserve.insert(wall.removeFirst(), at: 0) }
        return tile
    }

    private mutating func replaceFlowers(_ initial: Tile, for seat: Seat) -> Tile? {
        var tile = initial
        while needsFlowerReplacement(tile) {
            flowers[seat.id].append(tile)
            guard let next = replacement() else { return nil }
            tile = next
        }
        return tile
    }

    private mutating func gatherDrawn(for seat: Seat) {
        if let drawn { hands[seat.id].append(drawn) }
        drawn = nil
    }

    private mutating func sortHand(_ seat: Seat) {
        hands[seat.id].sort { ($0.kind, $0.id) < ($1.kind, $1.id) }
    }

    private mutating func finishWin(_ winner: Seat, kind: WinKind, tile: Tile, source: Seat?) {
        guard let gold else { return }
        let hand = hands[winner.id] + [tile]
        let lines: [RoundResult.Line]
        let patterns: [WinPattern]?
        let faceValueFlush: Bool?
        if ruleset == .legacy {
            lines = FuzhouScoring.lines(hand: hand, melds: melds[winner.id], flowers: flowers[winner.id],
                                        gold: gold.kind, dealer: winner == dealer, continuation: continuation,
                                        openingDraw: firstDraw, kind: kind)
            patterns = nil
            faceValueFlush = nil
        } else {
            (lines, patterns, faceValueFlush) = FuzhouScoring.modern(hand: hand, melds: melds[winner.id],
                flowers: flowers[winner.id], gold: gold, dealer: winner == dealer, continuation: continuation,
                kind: kind, ruleset: ruleset, houseRules: houseRules)
        }
        let payer = houseRules?.discardPayment == .allOpponents ? nil : source
        settle(RoundResult(winner: winner, kind: kind, source: payer, winningTile: tile,
                           winningHand: hand.sorted { $0.kind < $1.kind }, lines: lines, matchedPatterns: patterns,
                           pureSuitUsesFaceValues: faceValueFlush))
    }

    private mutating func settle(_ outcome: RoundResult) {
        result = outcome
        if step != .opening || outcome.kind != .robGold || outcome.winner == dealer { drawn = nil }
        offeredTile = nil
        responses = []
        step = .finished
        for seat in Seat.allCases { scores[seat.id] += outcome.delta(for: seat) }
    }

    private func utility(_ tile: Tile, in tiles: [Tile]) -> Int {
        if isGold(tile) { return 100 }
        return tiles.reduce(0) { score, other in
            guard other.id != tile.id, other.kind.suit == tile.kind.suit else { return score }
            switch abs(other.kind.rank - tile.kind.rank) {
            case 0: return score + 5
            case 1: return score + 2
            case 2: return score + 1
            default: return score
            }
        }
    }
}
