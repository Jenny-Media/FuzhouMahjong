import Foundation
import FuzhouCore
import Observation

@MainActor
@Observable
final class SoloMatch: MatchSession {
    private let storageKey: String
    private let defaults: UserDefaults
    private var match: FuzhouMatch?
    private(set) var revision = 0
    private(set) var openingRound: Int?
    var rackOrder: [Tile.ID]? {
        didSet {
            if let rackOrder { defaults.set(rackOrder, forKey: storageKey + ".rack-order") }
            else { defaults.removeObject(forKey: storageKey + ".rack-order") }
        }
    }

    init(storageKey: String = "solo-match.v2", defaults: UserDefaults = .standard) {
        self.storageKey = storageKey
        self.defaults = defaults
        if let saved = defaults.data(forKey: storageKey) {
            match = try? JSONDecoder().decode(FuzhouMatch.self, from: saved)
        }
        if match?.result == nil, match != nil {
            rackOrder = defaults.array(forKey: storageKey + ".rack-order") as? [Tile.ID]
        }
    }

    var table: TableState? { match?.table(for: FuzhouMatch.player) }
    var canResume: Bool { match != nil }
    var players: [RoomPlayer] { [] }
    var paused: Bool { false }
    var canAdvance: Bool { true }
    var computerHasMove: Bool { match?.hasComputerMove(excluding: [FuzhouMatch.player]) == true }

    func startIfNeeded() {
        guard match == nil else { return }
        startNew()
    }

    func startNew() {
        let newMatch = FuzhouMatch()
        rackOrder = nil
        openingRound = newMatch.roundNumber
        commit(newMatch)
    }

    func finishOpening(_ round: Int) {
        if openingRound == round { openingRound = nil }
    }

    func submit(_ move: Move) -> Bool {
        guard var updated = match, updated.apply(move, by: FuzhouMatch.player) else { return false }
        commit(updated)
        return true
    }

    func advanceComputer() {
        guard var updated = match, let (seat, move) = updated.nextComputerMove(excluding: [FuzhouMatch.player]),
              updated.apply(move, by: seat) else { return }
        commit(updated)
    }

    func nextHand() {
        guard var updated = match, updated.result != nil else { return }
        updated.nextRound()
        rackOrder = nil
        openingRound = updated.roundNumber
        commit(updated)
    }

    private func commit(_ updated: FuzhouMatch) {
        match = updated
        revision += 1
        if let data = try? JSONEncoder().encode(updated) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
