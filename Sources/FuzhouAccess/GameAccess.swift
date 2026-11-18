import Foundation
import Observation
import OSLog
import Security
import StoreKit

@MainActor
@Observable
public final class GameAccess {
    public static let trialID = "media.jenny.FuzhouMahjong.trial14"
    public static let lifetimeID = "media.jenny.FuzhouMahjong.lifetime"
    public static let archiveKey = "play-access.archive.v1"
    public private(set) var license: LicenseState
    public private(set) var archive: PlayArchive
    public private(set) var clock: Date
    public private(set) var products: [String: Product] = [:]
    public private(set) var busy = false
    public private(set) var loadingProducts = false
    public private(set) var catalogMessage: String?
    public private(set) var offlineCacheAvailable = true
    public private(set) var pending = Set<String>()
    public var message: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let vault: LicenseVault?
    @ObservationIgnored private let currentDate: @MainActor () -> Date
    @ObservationIgnored private let currentCalendar: @MainActor () -> Calendar
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var entitlementRevision = 0
    @ObservationIgnored private var started = false
    private static let storeLog = Logger(subsystem: "media.jenny.FuzhouMahjong", category: "StoreKit")

    public init(defaults: UserDefaults = .standard,
                keychainService: String? = Bundle.main.bundleIdentifier.map { $0 + ".verified-license.v1" },
                now: @escaping @MainActor () -> Date = { Date() },
                calendar: @escaping @MainActor () -> Calendar = {
                    var calendar = Calendar(identifier: .gregorian)
                    calendar.timeZone = .current
                    return calendar
                }) {
        self.defaults = defaults
        currentDate = now
        currentCalendar = calendar
        vault = keychainService.map(LicenseVault.init)
        license = vault?.read() ?? LicenseState()
        var stored = defaults.data(forKey: Self.archiveKey)
            .flatMap { try? JSONDecoder().decode(PlayArchive.self, from: $0) } ?? PlayArchive()
        for key in ["solo-match.v2", "solo-match.second.v1"] where stored.saves[key] == nil {
            if let match = defaults.data(forKey: key) {
                stored.saves[key] = SoloSave(match: match, rackOrder: defaults.array(forKey: key + ".rack-order") as? [Int])
            }
        }
        clock = stored.observe(now(), calendar: calendar())
        archive = stored
        persist()
    }

    deinit { listener?.cancel() }
    public var tier: AccessTier { license.tier(at: clock) }
    public var canHost: Bool { tier != .free }
    public var remainingSoloHands: Int { archive.remaining }
    public var canBeginSoloHand: Bool { tier != .free || remainingSoloHands > 0 }
    public var hasUsedTrial: Bool { archive.firstTrialStart != nil || license.trialStart != nil }
    public var trialProduct: Product? { products[Self.trialID] }
    public var lifetimeProduct: Product? { products[Self.lifetimeID] }
    public var trialEnd: Date? { license.trialStart?.addingTimeInterval(14 * 86_400) }

    public func refreshClock() {
        clock = archive.observe(currentDate(), calendar: currentCalendar())
        persist()
    }
    public func authorizeHosting() -> Bool { refreshClock(); return canHost }
    public func soloSave(key: String) -> SoloSave? { archive.saves[key] }
    public func beginSoloHand(key: String, match: Data) -> Bool {
        let allowed = archive.beginHand(key: key, save: SoloSave(match: match), license: license,
                                        at: currentDate(), calendar: currentCalendar())
        clock = archive.lastSeen ?? currentDate()
        persist()
        return allowed
    }
    public func saveSolo(key: String, match: Data, rackOrder: [Int]?) {
        guard var save = archive.saves[key] else { return }
        save.match = match
        save.rackOrder = rackOrder
        archive.saves[key] = save
        refreshClock()
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(archive) { defaults.set(data, forKey: Self.archiveKey) }
    }

    public func start() async {
        guard !started else { return }
        started = true
        listener = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled, let self else { return }
                await accept(result)
            }
        }
        await refreshEntitlements()
    }
    public func refreshEntitlements() async {
        let revision = entitlementRevision
        var refreshed = LicenseState()
        var firstTrial: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil,
                  transaction.productType == .nonConsumable else { continue }
            if transaction.productID == Self.lifetimeID { refreshed.lifetime = true }
            if transaction.productID == Self.trialID {
                refreshed.trialStart = transaction.originalPurchaseDate
                firstTrial = transaction.originalPurchaseDate
            }
        }
        if firstTrial == nil, let result = await Transaction.latest(for: Self.trialID),
           case .verified(let trial) = result { firstTrial = trial.originalPurchaseDate }
        // A purchase/update that arrived during enumeration is newer than this snapshot.
        guard entitlementRevision == revision else { await refreshEntitlements(); return }
        entitlementRevision += 1
        if let firstTrial { archive.recordTrialStart(firstTrial) }
        if let first = archive.firstTrialStart, refreshed.trialStart != nil { refreshed.trialStart = first }
        license = refreshed
        offlineCacheAvailable = vault?.write(license) ?? true
        refreshClock()
    }
    public func loadProducts() async {
        guard !loadingProducts else { return }
        loadingProducts = true
        defer { loadingProducts = false }
        do {
            let loaded = try await Product.products(for: [Self.trialID, Self.lifetimeID])
            guard !Task.isCancelled else { return }
            products = Dictionary(uniqueKeysWithValues: loaded.filter { $0.type == .nonConsumable }.map { ($0.id, $0) })
            if let trialProduct, trialProduct.price != 0 {
                Self.storeLog.error("The trial product returned a nonzero price")
                products.removeValue(forKey: Self.trialID)
            }
            switch (trialProduct != nil, lifetimeProduct != nil) {
            case (true, true): catalogMessage = nil
            case (false, true): catalogMessage = hasUsedTrial ? nil : "App Store 暂未提供免费体验。请重新读取购买信息。"
            case (_, false): catalogMessage = "App Store 未返回完整版价格。请检查媒体与购买项目的账号和地区，再重新读取。"
            }
            if products.count < 2 {
                let returned = loaded.map(\.id).sorted().joined(separator: ", ")
                Self.storeLog.warning("Incomplete product catalog. StoreKit returned [\(returned, privacy: .public)]")
            }
        } catch {
            guard !Task.isCancelled else { return }
            let error = error as NSError
            Self.storeLog.error("Product request failed: \(error.domain, privacy: .public) \(error.code)")
            catalogMessage = "暂时无法读取 App Store 的购买信息。请检查网络后重试。"
        }
    }
    public func purchase(_ productID: String) async {
        guard !busy, !loadingProducts, [Self.trialID, Self.lifetimeID].contains(productID) else { return }
        if productID == Self.trialID, hasUsedTrial {
            message = "14天免费体验已经开启过，恢复购买不会重新开始计时。"
            return
        }
        busy = true
        message = nil
        defer { busy = false }
        if products[productID] == nil { await loadProducts() }
        guard let product = products[productID] else { return }
        if productID == Self.trialID, lifetimeProduct == nil {
            message = "请先联网读取完整版价格，再确认开启免费体验。"
            return
        }
        do { await complete(try await product.purchase(), productID: productID) }
        catch StoreKitError.userCancelled { message = nil }
        catch Product.PurchaseError.purchaseNotAllowed {
            message = "此设备或账号当前不允许 App 内购买。请检查设备的购买限制。"
        } catch Product.PurchaseError.productUnavailable {
            catalogMessage = "当前 App Store 暂时无法提供此项目。请重新读取购买信息。"
            products.removeValue(forKey: productID)
        } catch StoreKitError.notAvailableInStorefront {
            catalogMessage = "此项目在当前 App Store 地区不可购买。请重新读取购买信息。"
            products.removeValue(forKey: productID)
        } catch {
            let error = error as NSError
            Self.storeLog.error("Purchase failed for \(productID, privacy: .public): \(error.domain, privacy: .public) \(error.code)")
            message = "购买未完成，请稍后重试。已有权限没有改变。"
        }
    }
    public func complete(_ result: Product.PurchaseResult, productID: String? = nil) async {
        switch result {
        case .success(let verification): await accept(verification)
        case .userCancelled: message = nil
        case .pending:
            if let productID { pending.insert(productID) }
            message = "正在等待购买批准。批准后会自动更新权限。"
        @unknown default: message = "购买尚未完成，请稍后重试。"
        }
    }
    private func accept(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            message = "无法验证这笔购买，请重试或恢复购买。"
            return
        }
        guard [Self.trialID, Self.lifetimeID].contains(transaction.productID),
              transaction.productType == .nonConsumable else { return }
        entitlementRevision += 1
        pending.remove(transaction.productID)
        if transaction.productID == Self.lifetimeID { license.lifetime = transaction.revocationDate == nil }
        else {
            archive.recordTrialStart(transaction.originalPurchaseDate)
            license.trialStart = transaction.revocationDate == nil ? archive.firstTrialStart : nil
        }
        offlineCacheAvailable = vault?.write(license) ?? true
        refreshClock()
        message = transaction.revocationDate == nil ? "权限已更新。已开启的权限可以离线使用。" : "购买已退款或撤销，当前这一局可以继续完成。"
        await transaction.finish()
    }
    public func restore() async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = tier == .lifetime ? "已恢复完整版权限。" : tier != .free ? "已恢复免费体验。" : "恢复完成，未找到有效的完整版权限或体验。"
        } catch { message = "暂时无法恢复购买。请联网后重试，已有权限没有改变。" }
    }
}

// Only verified StoreKit results reach this device-local cache. StoreKit's cached
// entitlement sequence reconciles it at launch/foreground, including revocations.
private struct LicenseVault {
    let service: String
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "verified-license"]
    }
    func read() -> LicenseState? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return nil }
        return try? JSONDecoder().decode(LicenseState.self, from: data)
    }
    func write(_ license: LicenseState) -> Bool {
        guard let data = try? JSONEncoder().encode(license) else { return false }
        let changes = [kSecValueData as String: data,
                       kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as [String: Any]
        let status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            changes.forEach { item[$0.key] = $0.value }
            return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }
}
