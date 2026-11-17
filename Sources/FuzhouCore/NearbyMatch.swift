import Foundation

public struct RoomPlayer: Equatable, Codable, Identifiable, Sendable {
    public var id: Seat { seat }
    public var seat: Seat
    public var name: String
    public var connected: Bool
}

public struct RoomUpdate: Equatable, Codable, Sendable {
    public var viewer: Seat
    public var players: [RoomPlayer]
    public var revision: Int
    public var table: TableState?
    public var paused: Bool
}

/// The host owns the wall and validates moves. A guest receives only their projected update.
public struct NearbyMatch: Sendable {
    private struct Reservation: Sendable {
        var key: UUID
        var player: RoomPlayer
    }

    private var reservations: [Reservation]
    private var match: FuzhouMatch?
    private var moveFloor = 0
    public private(set) var revision = 0

    public var players: [RoomPlayer] { reservations.map(\.player).sorted { $0.seat.id < $1.seat.id } }
    public var started: Bool { match != nil }
    public var paused: Bool { started && reservations.contains { !$0.player.connected } }
    public var canStart: Bool { !started && reservations.count >= 2 }
    public var humanSeats: Set<Seat> { Set(reservations.map(\.player.seat)) }

    public init(hostName: String) {
        reservations = [Reservation(key: UUID(), player: .init(seat: .east, name: hostName, connected: true))]
    }

    public mutating func join(key: UUID, name: String) -> Seat? {
        if let index = reservations.firstIndex(where: { $0.key == key && $0.player.seat != .east }) {
            reservations[index].player.connected = true
            bump()
            return reservations[index].player.seat
        }
        guard !started, let seat = Seat.allCases.first(where: { !humanSeats.contains($0) }) else { return nil }
        reservations.append(.init(key: key, player: .init(seat: seat, name: Self.normalizedName(name), connected: true)))
        bump()
        return seat
    }

    public mutating func disconnect(_ seat: Seat) {
        guard seat != .east, let index = reservations.firstIndex(where: { $0.player.seat == seat }) else { return }
        if started {
            reservations[index].player.connected = false
        } else {
            reservations.remove(at: index)
        }
        bump()
    }

    public mutating func release(_ seat: Seat) -> Bool {
        guard seat != .east, let index = reservations.firstIndex(where: { $0.player.seat == seat }) else {
            return false
        }
        reservations.remove(at: index)
        bump()
        return true
    }

    public mutating func start() -> Bool {
        guard canStart else { return false }
        match = FuzhouMatch()
        bump()
        return true
    }

    public func update(for seat: Seat) -> RoomUpdate {
        RoomUpdate(viewer: seat, players: players, revision: revision, table: match?.table(for: seat), paused: paused)
    }

    @discardableResult
    public mutating func submit(_ move: Move, seat: Seat, basedOn revision: Int) -> Bool {
        guard !paused, (moveFloor...self.revision).contains(revision), humanSeats.contains(seat) else { return false }
        return apply(move, seat: seat)
    }

    public var computerHasMove: Bool {
        !paused && match?.nextComputerMove(excluding: humanSeats) != nil
    }

    public mutating func advanceComputer() -> Bool {
        guard !paused, let (seat, move) = match?.nextComputerMove(excluding: humanSeats) else { return false }
        return apply(move, seat: seat)
    }

    public mutating func nextHand() -> Bool {
        guard !paused, match?.result != nil else { return false }
        match?.nextRound()
        bump()
        return true
    }

    private mutating func apply(_ move: Move, seat: Seat) -> Bool {
        let before = match?.table(for: seat)
        guard match?.apply(move, by: seat) == true else { return false }
        let after = match?.table(for: seat)
        let sameResponseWindow = (before?.step == .claim || before?.step == .opening) &&
            after?.step == before?.step && after?.offeredTile == before?.offeredTile
        bump(preserveWindow: sameResponseWindow)
        return true
    }

    private mutating func bump(preserveWindow: Bool = false) {
        revision += 1
        if !preserveWindow { moveFloor = revision }
    }

    public static func normalizedName(_ name: String) -> String {
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { !$0.isNewline && !$0.isASCIIControl }.prefix(12))
        return clean.isEmpty ? "牌友" : clean
    }
}

private extension Character {
    var isASCIIControl: Bool { asciiValue.map { $0 < 32 || $0 == 127 } ?? false }
}
