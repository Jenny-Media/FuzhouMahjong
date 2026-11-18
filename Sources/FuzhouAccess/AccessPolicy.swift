import Foundation

public enum AccessTier: Equatable, Sendable {
    case free, trial(ends: Date), lifetime
}

public struct LicenseState: Codable, Equatable, Sendable {
    public var lifetime = false
    public var trialStart: Date?
    public init(lifetime: Bool = false, trialStart: Date? = nil) {
        self.lifetime = lifetime
        self.trialStart = trialStart
    }
    public func tier(at date: Date) -> AccessTier {
        if lifetime { return .lifetime }
        if let start = trialStart, date >= start, date < start.addingTimeInterval(14 * 86_400) {
            return .trial(ends: start.addingTimeInterval(14 * 86_400))
        }
        return .free
    }
}

public struct SoloSave: Codable, Equatable, Sendable {
    public var match: Data
    public var rackOrder: [Int]?
    public var handID: UUID
    public init(match: Data, rackOrder: [Int]? = nil, handID: UUID = UUID()) {
        self.match = match
        self.rackOrder = rackOrder
        self.handID = handID
    }
}

public struct PlayArchive: Codable, Equatable, Sendable {
    public static let dailyLimit = 2
    public var saves: [String: SoloSave] = [:]
    public private(set) var lastSeen: Date?
    public private(set) var usageDay = ""
    public private(set) var used = 0
    public private(set) var firstTrialStart: Date?
    public init() {}

    public mutating func observe(_ date: Date, calendar: Calendar) -> Date {
        let effective = max(date, lastSeen ?? date)
        lastSeen = effective
        let parts = calendar.dateComponents([.year, .month, .day], from: effective)
        let day = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        // A backwards clock or westward time-zone change cannot replenish today's allowance.
        if day > usageDay { usageDay = day; used = 0 }
        return effective
    }
    public mutating func recordTrialStart(_ date: Date) {
        firstTrialStart = min(firstTrialStart ?? date, date)
    }
    public var remaining: Int { max(0, Self.dailyLimit - used) }

    public mutating func beginHand(key: String, save: SoloSave, license: LicenseState,
                                   at date: Date, calendar: Calendar) -> Bool {
        let effective = observe(date, calendar: calendar)
        if license.tier(at: effective) == .free {
            guard remaining > 0 else { return false }
            used += 1
        }
        // Match and allowance are encoded into one archive, so resuming never charges twice.
        saves[key] = save
        return true
    }
}
