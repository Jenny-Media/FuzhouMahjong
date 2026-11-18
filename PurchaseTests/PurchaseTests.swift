import FuzhouAccess
import FuzhouCore
import StoreKit
import Security
import StoreKitTest
import XCTest
@testable import FuzhouMahjong

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
        var family = FuzhouHouseRules(name: " Family ", keepDealerOnDraw: true)
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
        let first = SoloMatch(access: access)
        let second = SoloMatch(access: access, storageKey: "solo-match.second.v1")
        XCTAssertTrue(first.startIfNeeded())
        XCTAssertEqual(access.remainingSoloHands, 1)
        XCTAssertTrue(first.startIfNeeded())
        let reopened = SoloMatch(access: access)
        XCTAssertEqual(first.table, reopened.table)
        XCTAssertEqual(access.remainingSoloHands, 1)
        XCTAssertTrue(second.startNew())
        let saved = second.table
        XCTAssertFalse(second.startNew())
        XCTAssertEqual(second.table, saved)
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
            } else { solo.advanceComputer() }
        }
        XCTAssertNotNil(solo.table?.result)
        let result = solo.table
        solo.nextHand()
        XCTAssertEqual(solo.table, result)
    }
}
