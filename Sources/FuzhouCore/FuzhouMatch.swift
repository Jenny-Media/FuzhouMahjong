public struct FuzhouMatch: Equatable, Codable, Sendable {
    public static let rackSize = 16
    public static let player = Seat.south
    private static let scheduledHands = 16

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
    private var ponds = Array(repeating: [Tile](), count: 4)
    private var discardTimeline: [TableDiscard]?
    private var lastDraw: TableDraw?
    private var melds = Array(repeating: [Meld](), count: 4)
    private var selfDrawOnly = Set<Seat>()
    private var drew = Set<Seat>()
    private var firstDraw = false
    private var responses: [Response] = []
    private var step = TableState.Step.turn
    private var offeredTile: Tile?

    public private(set) var gold: Tile?
    public private(set) var current = Seat.east
    public private(set) var dealer = Seat.east
    public private(set) var drawn: Tile?
    public private(set) var result: RoundResult?
    public private(set) var scores = Array(repeating: 0, count: 4)
    public private(set) var roundNumber = 1
    public private(set) var dealerTurns = 0
    public private(set) var continuation = 0

    public var matchFinished: Bool {
        dealerTurns == Self.scheduledHands - 1 && result != nil && result?.winner != dealer
    }

    public init() {
        var random = SystemRandomNumberGenerator()
        self.init(using: &random)
    }

    public init<R: RandomNumberGenerator>(using random: inout R) {
        self.init(deck: Tile.fullSet.shuffled(using: &random))
    }

    init(deck: [Tile]) {
        deal(deck)
    }

    public func table(for viewer: Seat) -> TableState {
        TableState(viewer: viewer, hand: hands[viewer.id], drawn: current == viewer ? drawn : nil,
                   gold: gold, remaining: wall.count, dealer: dealer, continuation: continuation,
                   roundNumber: roundNumber, wind: Seat.allCases[dealerTurns / 4],
                   handNumber: dealerTurns % 4 + 1, matchFinished: matchFinished, current: current,
                   step: step, offeredTile: offeredTile, moves: legalMoves(for: viewer),
                   players: Seat.allCases.map {
                       .init(seat: $0, rackCount: hands[$0.id].count, flowerCount: flowers[$0.id].count,
                             discards: ponds[$0.id], melds: melds[$0.id], score: scores[$0.id])
                   }, result: result, discardTimeline: discardTimeline, lastDraw: lastDraw)
    }

    public func legalMoves(for seat: Seat) -> [Move] {
        switch step {
        case .finished:
            return []
        case .opening:
            guard responses.contains(.pending(seat)) else { return [] }
            return [.win, .pass]
        case .claim:
            guard responses.contains(.pending(seat)), let offeredTile else { return [] }
            return discardClaims(for: seat, tile: offeredTile) + [.pass]
        case .turn:
            guard seat == current else { return [] }
            let rack = combinedHand(for: seat)
            var moves = rack.filter { !$0.kind.isFlower }.map { Move.discard($0.id) }
            // A matching honor or season drawn after the reveal can either stay as gold or be replaced as a flower.
            if !reserve.isEmpty {
                moves += rack.filter { $0.kind.isFlower && isGold($0) }.map { Move.replaceFlower($0.id) }
            }
            if drawn != nil, canWin(seat, tiles: rack) { moves.insert(.win, at: 0) }
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
            if !responses.contains(where: { if case .pending = $0 { true } else { false } }) {
                resolveResponses()
            }
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
            if step == .claim, let pung = moves.first(where: {
                if case .meld(.pung, _) = $0 { true } else { false }
            }) {
                return (seat, pung)
            }
            if moves.contains(.pass) { return (seat, .pass) }
            let tiles = combinedHand(for: seat)
            let discardable = Set(moves.compactMap { if case .discard(let id) = $0 { id } else { nil } })
            if let tile = tiles.filter({ discardable.contains($0.id) }).min(by: {
                (utility($0, in: tiles), $0.id) < (utility($1, in: tiles), $1.id)
            }) {
                return (seat, .discard(tile.id))
            }
            if let fallback = moves.first { return (seat, fallback) }
        }
        return nil
    }

    public mutating func nextRound() {
        guard let result else { return }
        if matchFinished {
            self = FuzhouMatch()
            return
        }
        if result.winner == dealer {
            continuation += 1
        } else {
            dealer = dealer.advanced(1)
            dealerTurns += 1
            continuation = result.winner == nil ? continuation + 1 : 0
        }
        roundNumber += 1
        var random = SystemRandomNumberGenerator()
        deal(Tile.fullSet.shuffled(using: &random))
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
        for offset in 0..<4 {
            let seat = dealer.advanced(offset)
            let dealt = hands[seat.id]
            hands[seat.id] = []
            for tile in dealt {
                guard let ready = replaceFlowers(tile, for: seat) else { settle(.draw); return }
                hands[seat.id].append(ready)
            }
            sortHand(seat)
        }

        guard reserve.count >= 2 else { settle(.draw); return }
        let indicator = reserve.remove(at: reserve.count - 2)
        gold = indicator
        // The reveal must complete the original hand as a tile, before gold begins acting as a joker.
        responses = (0..<4).map { dealer.advanced($0) }.filter { seat in
            WinningHand.isComplete((hands[seat.id] + [indicator]).map(\.kind), gold: nil)
        }.map(Response.pending)
        if responses.isEmpty { drawTurn() }
    }

    private mutating func resetHandState() {
        ponds = Array(repeating: [], count: 4)
        discardTimeline = []
        lastDraw = nil
        melds = Array(repeating: [], count: 4)
        selfDrawOnly = []
        drew = []
        firstDraw = false
        responses = []
        offeredTile = nil
    }

    private func isGold(_ tile: Tile) -> Bool { gold.map { tile.kind.matchesGold($0.kind) } ?? false }

    private func combinedHand(for seat: Seat) -> [Tile] {
        hands[seat.id] + (seat == current ? [drawn].compactMap { $0 } : [])
    }

    private func canWin(_ seat: Seat, tiles: [Tile]) -> Bool {
        WinningHand.isComplete(tiles.map(\.kind), gold: gold?.kind, melds: melds[seat.id].count)
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
        gatherDrawn(for: seat)
        let tile = removeTiles([id], from: seat)[0]
        sortHand(seat)
        if isGold(tile) { selfDrawOnly.insert(seat) }
        ponds[seat.id].append(tile)
        if discardTimeline == nil { discardTimeline = [] }
        discardTimeline?.append(TableDiscard(seat: seat, tile: tile))
        firstDraw = false
        offeredTile = tile
        step = .claim
        responses = (1..<4).map { seat.advanced($0) }.filter {
            !discardClaims(for: $0, tile: tile).isEmpty
        }.map(Response.pending)
        if responses.isEmpty { resolveResponses() }
    }

    private mutating func resolveResponses() {
        let choices: [(Seat, Move)] = responses.compactMap {
            guard case let .chose(seat, move) = $0, move != .pass else { return nil }
            return (seat, move)
        }
        responses = []
        if step == .opening {
            if let (winner, _) = choices.first, let gold {
                finishWin(winner, kind: .robGold, tile: gold, source: nil)
            } else {
                drawTurn()
            }
            return
        }

        let source = current
        defer { offeredTile = nil }
        if let tile = offeredTile, let (seat, move) = choices
            .enumerated().max(by: { (priority($0.element.1), -$0.offset) < (priority($1.element.1), -$1.offset) })?.element {
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

    private func priority(_ move: Move) -> Int {
        switch move { case .win: 3; case .meld(let kind, _): kind.priority; default: 0 }
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
        while tile.kind.isFlower && !isGold(tile) {
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
        let lines = FuzhouScoring.lines(hand: hand, melds: melds[winner.id], flowers: flowers[winner.id],
                                       gold: gold.kind, dealer: winner == dealer, continuation: continuation,
                                       openingDraw: firstDraw, kind: kind)
        settle(RoundResult(winner: winner, kind: kind, source: source, winningTile: tile,
                           winningHand: hand.sorted { $0.kind < $1.kind }, lines: lines))
    }

    private mutating func settle(_ outcome: RoundResult) {
        result = outcome
        drawn = nil
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
