import Foundation
import FuzhouAccess
import FuzhouCore
import Observation

@MainActor
@Observable
final class SoloMatch: MatchSession {
    private let storageKey: String
    private let access: GameAccess
    private var match: FuzhouMatch?
    private(set) var revision = 0
    private(set) var openingRound: Int?
    var rackOrder: [Tile.ID]? { didSet { persist() } }

    init(access: GameAccess, storageKey: String = "solo-match.v2") {
        self.storageKey = storageKey
        self.access = access
        if let save = access.soloSave(key: storageKey) {
            match = try? JSONDecoder().decode(FuzhouMatch.self, from: save.match)
            if match?.result == nil { rackOrder = save.rackOrder }
        }
    }

    var table: TableState? { match?.table(for: FuzhouMatch.player) }
    var canResume: Bool { match != nil }
    var players: [RoomPlayer] { [] }
    var paused: Bool { false }
    var canAdvance: Bool { true }
    var computerHasMove: Bool { match?.hasComputerMove(excluding: [FuzhouMatch.player]) == true }

    @discardableResult func startIfNeeded(ruleset: FuzhouRuleset = .pureSuit, houseRules: FuzhouHouseRules? = nil) -> Bool {
        if match != nil { return true }
        return startNew(ruleset: ruleset, houseRules: houseRules)
    }
    @discardableResult func startNew(ruleset: FuzhouRuleset = .pureSuit, houseRules: FuzhouHouseRules? = nil) -> Bool {
        begin(FuzhouMatch(ruleset: ruleset, houseRules: houseRules))
    }
    private func begin(_ updated: FuzhouMatch) -> Bool {
        guard let data = try? JSONEncoder().encode(updated),
              access.beginSoloHand(key: storageKey, match: data) else { return false }
        match = updated
        rackOrder = nil
        openingRound = updated.roundNumber
        revision += 1
        return true
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
        _ = begin(updated)
    }
    private func commit(_ updated: FuzhouMatch) {
        match = updated
        revision += 1
        persist()
    }
    private func persist() {
        guard let match, let data = try? JSONEncoder().encode(match) else { return }
        access.saveSolo(key: storageKey, match: data, rackOrder: rackOrder)
    }
}
