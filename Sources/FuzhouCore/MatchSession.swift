import Observation

@MainActor
public protocol MatchSession: AnyObject, Observable {
    var table: TableState? { get }
    var revision: Int { get }
    var players: [RoomPlayer] { get }
    var paused: Bool { get }
    var canAdvance: Bool { get }
    var computerHasMove: Bool { get }
    var openingRound: Int? { get }
    func finishOpening(_ round: Int)
    func submit(_ move: Move) -> Bool
    func advanceComputer()
    func nextHand()
}
