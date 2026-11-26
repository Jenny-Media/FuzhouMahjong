import FuzhouAccess
import FuzhouCore
import StoreKit
import Security
import StoreKitTest
import XCTest
@testable import FuzhouMahjong

@MainActor
final class SoloSaveMigrationTests: XCTestCase {
    func testResumingAfterADealerChangeOnlyRemovesImpossibleRepeats() throws {
        let game = FuzhouMatch()
        let encoder = JSONEncoder()
        var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(game)) as? [String: Any])
        saved["dealer"] = Seat.south.id
        saved["dealerTurns"] = 1
        let even = [0, 0, 0, 0]
        for (round, stored, scores, expected) in [
            (2, 1, even, 0), (4, 2, even, 2), (4, 3, even, 1),
            (3, 2, [30, -10, -10, -10], 0), // East won, then a draw passed the deal.
            (3, 2, [-12, 36, -12, -12], 1), // A draw passed the deal, then South won at the old +2 bonus.
        ] {
            let suite = "DealerRestoreTests." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let access = GameAccess(defaults: defaults, keychainService: nil)
            saved["roundNumber"] = round
            saved["continuation"] = stored
            saved["scores"] = scores
            let key = SoloSaveSlot.first.rawValue
            XCTAssertTrue(access.beginSoloHand(key: key, match: try JSONSerialization.data(withJSONObject: saved)))
            let remaining = access.remainingSoloHands
            let resumed = SoloMatch(access: access)
            XCTAssertEqual(resumed.table?.continuation, expected)
            let archive = try XCTUnwrap(access.soloSave(key: key))
            XCTAssertEqual(try JSONDecoder().decode(FuzhouMatch.self, from: archive.match).continuation, expected)
            XCTAssertEqual(access.remainingSoloHands, remaining)
        }
    }

    func testCancelledComputerTurnDoesNotAdvanceOrOverwriteTheSave() async throws {
        let suite = "SoloComputerTurnTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let access = GameAccess(defaults: defaults, keychainService: nil)
        let player = FuzhouMatch.player
        var match = FuzhouMatch()
        for _ in 0..<4 where !match.hasComputerMove(excluding: [player]) {
            let move = try XCTUnwrap(match.legalMoves(for: player).first { $0 != .win })
            XCTAssertTrue(match.apply(move, by: player))
        }
        _ = match.settleRestoredDiscard()
        let (seat, move) = try XCTUnwrap(match.nextComputerMove(excluding: [player]))
        let key = SoloSaveSlot.first.rawValue
        let saved = try JSONEncoder().encode(match)
        XCTAssertTrue(access.beginSoloHand(key: key, match: saved))
        let solo = SoloMatch(access: access)
        let revision = solo.revision

        let cancelled = Task { await solo.advanceComputer() }
        cancelled.cancel()
        await cancelled.value
        XCTAssertEqual(solo.revision, revision)
        XCTAssertEqual(access.soloSave(key: key)?.match, saved)

        await solo.advanceComputer()
        XCTAssertTrue(match.apply(move, by: seat))
        XCTAssertEqual(solo.revision, revision + 1)
        XCTAssertEqual(solo.table, match.table(for: player))
        let updatedSave = try XCTUnwrap(access.soloSave(key: key)?.match)
        XCTAssertEqual(try JSONDecoder().decode(FuzhouMatch.self, from: updatedSave), match)
    }

    func testRetiringLegacySoloTablesPreservesCurrentSavesAndUsage() throws {
        let encoder = JSONEncoder()
        let legacy = try encoder.encode(FuzhouMatch(ruleset: .legacy))
        let current = FuzhouMatch(houseRules: .init(name: "Family", goldIndicators: .includeDragons))
        let currentSave = try encoder.encode(current)

        for legacyInFirstSlot in [true, false] {
            let suite = "SoloSaveMigrationTests." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }

            let oldKey = legacyInFirstSlot ? "solo-match.v2" : "solo-match.second.v1"
            let currentKey = legacyInFirstSlot ? "solo-match.second.v1" : "solo-match.v2"
            defaults.set(legacy, forKey: oldKey)
            defaults.set([1, 2], forKey: oldKey + ".rack-order")
            let access = GameAccess(defaults: defaults, keychainService: nil)
            XCTAssertTrue(access.beginSoloHand(key: currentKey, match: currentSave))
            let savedOrder = current.table(for: .south).hand.reversed().map(\.id)
            access.saveSolo(key: currentKey, match: currentSave, rackOrder: savedOrder)
            let before = access.soloSave(key: currentKey)

            let resumed = SoloMatch(access: access)
            XCTAssertTrue(resumed.removedLegacySave)
            XCTAssertEqual(resumed.table, current.table(for: .south))
            XCTAssertEqual(resumed.rackOrder, savedOrder)
            XCTAssertNil(defaults.data(forKey: oldKey))
            XCTAssertNil(defaults.array(forKey: oldKey + ".rack-order"))
            XCTAssertEqual(access.remainingSoloHands, 1)

            let reopened = GameAccess(defaults: defaults, keychainService: nil)
            XCTAssertNil(reopened.soloSave(key: SoloSaveSlot.second.rawValue))
            XCTAssertEqual(reopened.soloSave(key: SoloSaveSlot.first.rawValue), before)
            XCTAssertFalse(SoloMatch(access: reopened).removedLegacySave)
        }
    }

    func testTwoCurrentSavesWaitForAChoiceAndKeepTheExactChosenSave() throws {
        let encoder = JSONEncoder()
        let first = FuzhouMatch(ruleset: .oldThree)
        let second = FuzhouMatch(houseRules: .init(name: "Family", goldIndicators: .includeDragons))
        for slotToKeep in SoloSaveSlot.allCases {
            let suite = "SoloSaveMigrationTests." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let access = GameAccess(defaults: defaults, keychainService: nil)
            for (slot, match) in [(SoloSaveSlot.first, first), (.second, second)] {
                let data = try encoder.encode(match)
                let key = slot.rawValue
                defaults.set(data, forKey: key)
                XCTAssertTrue(access.beginSoloHand(key: key, match: data))
                access.saveSolo(key: key, match: data, rackOrder: match.table(for: .south).hand.reversed().map(\.id))
            }
            let original = access.archive.saves
            let pending = SoloMatch(access: access)
            XCTAssertNil(pending.table)
            XCTAssertEqual(pending.savedTableChoices.map(\.slot), SoloSaveSlot.allCases)
            XCTAssertFalse(pending.startNew())
            XCTAssertEqual(access.archive.saves, original)

            let reopened = GameAccess(defaults: defaults, keychainService: nil)
            let choosing = SoloMatch(access: reopened)
            XCTAssertEqual(choosing.savedTableChoices.count, 2)
            XCTAssertTrue(choosing.keepSavedTable(slotToKeep))
            XCTAssertTrue(choosing.savedTableChoices.isEmpty)
            XCTAssertEqual(choosing.table, (slotToKeep == .first ? first : second).table(for: .south))
            XCTAssertEqual(reopened.remainingSoloHands, 0)

            let final = GameAccess(defaults: defaults, keychainService: nil)
            XCTAssertEqual(final.soloSave(key: SoloSaveSlot.first.rawValue), original[slotToKeep.rawValue])
            XCTAssertNil(final.soloSave(key: SoloSaveSlot.second.rawValue))
            XCTAssertNil(defaults.data(forKey: SoloSaveSlot.second.rawValue))
        }
    }
}

@MainActor
final class CustomRulesPersistenceTests: XCTestCase {
    func testFivePresetLimitAllowsEditsAndFreesASlotOnDelete() throws {
        let suite = "CustomRulesPersistenceTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let library = RulesetLibrary(defaults: defaults)
        for index in 1...5 { XCTAssertTrue(library.save(FuzhouHouseRules(name: "Preset \(index)"))) }
        let loaded = RulesetLibrary(defaults: defaults)
        let extra = FuzhouHouseRules(name: "Preset 6")
        XCTAssertFalse(loaded.canAddPreset)
        XCTAssertFalse(loaded.save(extra))
        XCTAssertEqual(loaded.presets.count, 5)

        var edited = try XCTUnwrap(loaded.presets.first)
        edited.name = "Renamed"
        XCTAssertTrue(loaded.save(edited))
        XCTAssertEqual(loaded.presets.first, edited)
        XCTAssertTrue(loaded.delete(edited.id))
        XCTAssertTrue(loaded.canAddPreset)
        XCTAssertTrue(loaded.save(extra))
        XCTAssertEqual(RulesetLibrary(defaults: defaults).presets.count, 5)
    }

    func testExistingLibraryAboveTheLimitKeepsItsPresets() throws {
        let suite = "CustomRulesPersistenceTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let existing = (1...6).map { FuzhouHouseRules(name: "Existing \($0)") }
        defaults.set(try JSONEncoder().encode(existing), forKey: "table.custom-rulesets.v1")
        let library = RulesetLibrary(defaults: defaults)
        XCTAssertEqual(library.presets, existing)
        XCTAssertFalse(library.canAddPreset)
        var edited = try XCTUnwrap(library.presets.last)
        edited.name = "Edited"
        XCTAssertTrue(library.save(edited))
        XCTAssertEqual(library.presets.count, 6)
    }

    func testSavedRulesCanBeEditedAndDeletedIndependently() throws {
        let suite = "CustomRulesPersistenceTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let library = RulesetLibrary(defaults: defaults)
        var family = FuzhouHouseRules(name: " Family ", keepDealerOnDraw: true, goldIndicators: .includeWinds)
        let friends = FuzhouHouseRules(name: "Friends", flush: .faceValue, stackBonuses: true)
        XCTAssertTrue(library.save(family))
        XCTAssertTrue(library.save(friends))
        XCTAssertFalse(library.save(FuzhouHouseRules(name: "family")))

        let loaded = RulesetLibrary(defaults: defaults)
        XCTAssertEqual(loaded.presets.map(\.name), ["Family", "Friends"])
        family.name = "Family revised"
        XCTAssertTrue(loaded.save(family))
        XCTAssertEqual(loaded.preset(for: family.id.uuidString), family)
        XCTAssertTrue(loaded.delete(family.id))
        XCTAssertEqual(RulesetLibrary(defaults: defaults).presets, [friends])
    }
}

@MainActor
final class PurchaseTests: XCTestCase {
    private var session: SKTestSession!
    private var defaults: UserDefaults!
    private var suite: String!
    private var date = Date()
    override func setUp() async throws {
        continueAfterFailure = true
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "FuzhouMahjong", withExtension: "storekit"))
        session = try SKTestSession(contentsOf: file)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        suite = "FuzhouPurchaseTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        date = Date()
    }
    override func tearDown() async throws {
        session.clearTransactions()
        defaults.removePersistentDomain(forName: suite)
        session = nil
    }
    private func manager() -> GameAccess {
        GameAccess(defaults: defaults, keychainService: nil, now: { self.date })
    }
    private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(condition())
    }
    func testCatalogHasAFreeTrialAndFourNinetyNineLifetimeUnlock() async throws {
        let access = manager()
        await access.loadProducts()
        XCTAssertEqual(try XCTUnwrap(access.trialProduct).price, 0)
        XCTAssertEqual(try XCTUnwrap(access.lifetimeProduct).price, Decimal(string: "4.99"))
        XCTAssertFalse(access.authorizeHosting())
    }
    func testRetryClearsTheCatalogErrorAndLoadsBothProducts() async throws {
        let access = manager()
        try await session.setSimulatedError(.generic(.unknown), forAPI: .loadProducts)
        await access.loadProducts()
        XCTAssertNotNil(access.catalogMessage)
        XCTAssertNil(access.message)
        XCTAssertNil(access.lifetimeProduct)

        try await session.setSimulatedError(nil, forAPI: .loadProducts)
        await access.loadProducts()
        XCTAssertNotNil(access.trialProduct)
        XCTAssertNotNil(access.lifetimeProduct)
        XCTAssertNil(access.catalogMessage)
    }
    func testActualTrialPurchaseRestoreAndExpiryDoNotRestartTheClock() async throws {
        let access = manager()
        await access.start()
        await access.purchase(GameAccess.trialID)
        let transaction = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == GameAccess.trialID })
        let start = try XCTUnwrap(access.license.trialStart)
        date = start.addingTimeInterval(1)
        access.refreshClock()
        XCTAssertTrue(access.authorizeHosting())
        let reopened = manager()
        await reopened.start()
        XCTAssertEqual(reopened.license.trialStart, start)
        date = start.addingTimeInterval(14 * 86_400)
        reopened.refreshClock()
        XCTAssertFalse(reopened.authorizeHosting())
        XCTAssertTrue(reopened.hasUsedTrial)
        await reopened.purchase(GameAccess.trialID)
        XCTAssertEqual(session.allTransactions().filter { $0.productIdentifier == GameAccess.trialID }.count, 1)
        XCTAssertEqual(session.allTransactions().first?.identifier, transaction.identifier)
        XCTAssertTrue(reopened.beginSoloHand(key: "one", match: Data()))
        XCTAssertTrue(reopened.beginSoloHand(key: "two", match: Data()))
        XCTAssertFalse(reopened.beginSoloHand(key: "three", match: Data()))
    }
    func testLifetimeUnlocksSoloAndHostingAndRefundRevokesFutureAccess() async throws {
        let access = manager()
        await access.start()
        await access.purchase(GameAccess.lifetimeID)
        let purchase = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == GameAccess.lifetimeID })
        XCTAssertEqual(access.tier, .lifetime)
        for i in 0..<4 { XCTAssertTrue(access.beginSoloHand(key: "\(i)", match: Data())) }
        XCTAssertTrue(access.authorizeHosting())
        let restored = manager()
        await restored.start()
        XCTAssertEqual(restored.tier, .lifetime)
        await restored.restore()
        XCTAssertEqual(restored.tier, .lifetime)
        try session.refundTransaction(identifier: purchase.identifier)
        try await eventually { access.tier == .free }
        XCTAssertFalse(access.authorizeHosting())
    }
    func testCancelledPendingUnverifiedAndFailedPurchasesDoNotUnlock() async throws {
        let access = manager()
        await access.complete(.userCancelled)
        XCTAssertNil(access.message)
        await access.complete(.pending, productID: GameAccess.lifetimeID)
        XCTAssertEqual(access.tier, .free)
        XCTAssertTrue(access.pending.contains(GameAccess.lifetimeID))
        // Use the trial to create a signed fixture so StoreKit has no existing lifetime purchase to return.
        let transaction = try await session.buyProduct(identifier: GameAccess.trialID)
        await access.complete(.success(.unverified(transaction, .invalidSignature)))
        XCTAssertEqual(access.tier, .free)
        session.clearTransactions()
        try await session.setSimulatedError(.purchase(.purchaseNotAllowed), forAPI: .purchase)
        await access.purchase(GameAccess.lifetimeID)
        try await session.setSimulatedError(nil, forAPI: .purchase)
        XCTAssertEqual(access.tier, .free)
        XCTAssertNotNil(access.message)
    }
    func testCachedVerifiedLicenseCanAuthorizeBeforeAnyNetworkRequest() async throws {
        let service = "FuzhouPurchasesTests.Cache." + UUID().uuidString
        defer { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary) }
        let access = GameAccess(defaults: defaults, keychainService: service)
        await access.purchase(GameAccess.lifetimeID)
        XCTAssertEqual(access.tier, .lifetime)
        let offlineRelaunch = GameAccess(defaults: defaults, keychainService: service)
        // No StoreKit start, product request, restore or server call has occurred on this instance.
        XCTAssertEqual(offlineRelaunch.tier, .lifetime)
        XCTAssertTrue(offlineRelaunch.authorizeHosting())
        XCTAssertTrue(offlineRelaunch.beginSoloHand(key: "offline", match: Data()))
        session.clearTransactions()
        await offlineRelaunch.refreshEntitlements()
        XCTAssertEqual(offlineRelaunch.tier, .free)
    }
    func testSoloResumeDoesNotSpendQuotaAndBlockedRestartPreservesTheSavedGame() throws {
        let access = manager()
        let solo = SoloMatch(access: access)
        XCTAssertTrue(solo.startIfNeeded())
        XCTAssertEqual(access.remainingSoloHands, 1)
        XCTAssertTrue(solo.startIfNeeded())
        let reopened = SoloMatch(access: access)
        XCTAssertEqual(solo.table, reopened.table)
        XCTAssertEqual(access.remainingSoloHands, 1)
        XCTAssertTrue(reopened.startNew(ruleset: .oldThree))
        let saved = reopened.table
        XCTAssertEqual(saved?.ruleset, .oldThree)
        XCTAssertFalse(reopened.startNew(ruleset: .pureSuit))
        XCTAssertEqual(reopened.table, saved)
        XCTAssertEqual(access.remainingSoloHands, 0)
    }
    func testTrialExpiryAllowsCurrentHandToFinishButBlocksNextHandAfterFreeAllowance() async throws {
        let access = manager()
        await access.start()
        await access.purchase(GameAccess.trialID)
        let start = try XCTUnwrap(access.license.trialStart)
        let solo = SoloMatch(access: access)
        XCTAssertTrue(solo.startNew())
        solo.finishOpening(1)
        date = start.addingTimeInterval(14 * 86_400 + 1)
        access.refreshClock()
        _ = access.beginSoloHand(key: "other-one", match: Data())
        _ = access.beginSoloHand(key: "other-two", match: Data())
        for _ in 0..<400 where solo.table?.result == nil {
            guard let table = solo.table else { XCTFail(); return }
            if let move = table.moves.first {
                let selected = table.moves.first { if case .discard = $0 { true } else { false } } ?? move
                XCTAssertTrue(solo.submit(selected))
            } else { await solo.advanceComputer() }
        }
        XCTAssertNotNil(solo.table?.result)
        let result = solo.table
        solo.nextHand()
        XCTAssertEqual(solo.table, result)
    }
}
