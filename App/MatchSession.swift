import Foundation
import FuzhouAccess
import FuzhouCore
import Observation

@MainActor
@Observable
final class SoloMatch: MatchSession {
    struct SavedTable: Identifiable {
        let slot: SoloSaveSlot
        fileprivate let match: FuzhouMatch
        fileprivate let rackOrder: [Tile.ID]?
        fileprivate let settledDiscard: Bool
        var id: SoloSaveSlot { slot }
        var table: TableState { match.table(for: FuzhouMatch.player) }
    }

    private let storageKey = SoloSaveSlot.first.rawValue
    private let access: GameAccess
    @ObservationIgnored private var match: FuzhouMatch?
    private(set) var table: TableState?
    private(set) var removedLegacySave = false
    private(set) var savedTableChoices: [SavedTable] = []
    private(set) var revision = 0
    private(set) var openingRound: Int?
    private var storedRackOrder: [Tile.ID]?
    var rackOrder: [Tile.ID]? {
        get { storedRackOrder }
        set {
            storedRackOrder = newValue
            persist()
        }
    }

    init(access: GameAccess) {
        self.access = access
        let savedTables = SoloSaveSlot.allCases.compactMap { slot -> SavedTable? in
            guard let save = access.soloSave(key: slot.rawValue),
                  var savedMatch = try? JSONDecoder().decode(FuzhouMatch.self, from: save.match) else { return nil }
            guard savedMatch.ruleset != .legacy else {
                access.removeSoloSave(key: slot.rawValue)
                removedLegacySave = true
                return nil
            }
            let settledDiscard = savedMatch.settleRestoredDiscard()
            return SavedTable(slot: slot, match: savedMatch, rackOrder: savedMatch.result == nil ? save.rackOrder : nil,
                              settledDiscard: settledDiscard)
        }

        if savedTables.count == 1, let saved = savedTables.first,
           saved.slot == .first || retain(saved) {
            restore(saved)
            if saved.slot == .first, saved.settledDiscard { persist() }
        } else {
            savedTableChoices = savedTables
        }
    }

    func keepSavedTable(_ slot: SoloSaveSlot) -> Bool {
        guard let saved = savedTableChoices.first(where: { $0.slot == slot }),
              retain(saved) else { return false }
        restore(saved)
        savedTableChoices = []
        revision += 1
        return true
    }

    private func retain(_ saved: SavedTable) -> Bool {
        guard saved.settledDiscard else { return access.retainSoloSave(saved.slot) }
        guard let data = try? JSONEncoder().encode(saved.match) else { return false }
        return access.retainSoloSave(saved.slot, replacingWith: (match: data, rackOrder: saved.rackOrder))
    }

    private func restore(_ saved: SavedTable) {
        updateMatch(saved.match)
        storedRackOrder = saved.rackOrder
    }

    var canResume: Bool { table != nil }
    var players: [RoomPlayer] { [] }
    var paused: Bool { false }
    var canAdvance: Bool { true }
    var computerHasMove: Bool { match?.hasComputerMove(excluding: [FuzhouMatch.player]) == true }

    @discardableResult func startIfNeeded(ruleset: FuzhouRuleset = .pureSuit, houseRules: FuzhouHouseRules? = nil) -> Bool {
        if match != nil { return true }
        return startNew(ruleset: ruleset, houseRules: houseRules)
    }
    @discardableResult func startNew(ruleset: FuzhouRuleset = .pureSuit, houseRules: FuzhouHouseRules? = nil) -> Bool {
        guard savedTableChoices.isEmpty else { return false }
        return begin(FuzhouMatch(ruleset: ruleset == .legacy ? .pureSuit : ruleset, houseRules: houseRules))
    }
    private func begin(_ updated: FuzhouMatch) -> Bool {
        guard let data = try? JSONEncoder().encode(updated),
              access.beginSoloHand(key: storageKey, match: data) else { return false }
        updateMatch(updated)
        storedRackOrder = nil
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
    func advanceComputer() async {
        guard let match, !Task.isCancelled else { return }
        let expectedRevision = revision
        let worker = Task.detached(priority: .userInitiated) { () -> FuzhouMatch? in
            var updated = match
            guard !Task.isCancelled,
                  let (seat, move) = updated.nextComputerMove(excluding: [FuzhouMatch.player]),
                  !Task.isCancelled, updated.apply(move, by: seat) else { return nil }
            return updated
        }
        let updated = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard let updated, !Task.isCancelled, revision == expectedRevision else { return }
        commit(updated)
    }
    func nextHand() {
        guard var updated = match, updated.result != nil else { return }
        updated.nextRound()
        _ = begin(updated)
    }
    private func commit(_ updated: FuzhouMatch) {
        updateMatch(updated)
        revision += 1
        persist()
    }
    private func updateMatch(_ updated: FuzhouMatch) {
        match = updated
        table = updated.table(for: FuzhouMatch.player, revealsSettledHands: true)
    }
    private func persist() {
        guard let match, let data = try? JSONEncoder().encode(match) else { return }
        access.saveSolo(key: storageKey, match: data, rackOrder: rackOrder)
    }
}
