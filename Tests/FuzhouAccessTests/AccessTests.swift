import Foundation
import XCTest
@testable import FuzhouAccess

final class AccessTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }

    func testTrialWindowIsExactlyFourteenDaysAndLifetimeDoesNotExpire() {
        let trial = LicenseState(trialStart: start)
        XCTAssertEqual(trial.tier(at: start.addingTimeInterval(-1)), .free)
        XCTAssertNotEqual(trial.tier(at: start), .free)
        XCTAssertNotEqual(trial.tier(at: start.addingTimeInterval(14 * 86_400 - 1)), .free)
        XCTAssertEqual(trial.tier(at: start.addingTimeInterval(14 * 86_400)), .free)
        XCTAssertEqual(LicenseState(lifetime: true).tier(at: start.addingTimeInterval(50 * 365 * 86_400)), .lifetime)
    }
    func testTwoHandsShareOneAllowanceAcrossSaveSlotsAndBlockedRestartPreservesSave() throws {
        var archive = PlayArchive()
        let first = SoloSave(match: Data("first".utf8))
        let second = SoloSave(match: Data("second".utf8))
        XCTAssertTrue(archive.beginHand(key: "main", save: first, license: .init(), at: start, calendar: calendar))
        XCTAssertTrue(archive.beginHand(key: "second", save: second, license: .init(), at: start, calendar: calendar))
        XCTAssertFalse(archive.beginHand(key: "main", save: second, license: .init(), at: start, calendar: calendar))
        XCTAssertEqual(archive.saves["main"], first)
        let restored = try JSONDecoder().decode(PlayArchive.self, from: JSONEncoder().encode(archive))
        XCTAssertEqual(restored.remaining, 0)
        XCTAssertEqual(restored.saves["main"]?.handID, first.handID)
    }
    func testLocalMidnightResetsAndClockRollbackCannotAddHands() {
        var archive = PlayArchive()
        let midnight = calendar.startOfDay(for: start)
        let before = midnight.addingTimeInterval(-1)
        for _ in 0..<2 { XCTAssertTrue(archive.beginHand(key: "main", save: .init(match: Data()), license: .init(), at: before, calendar: calendar)) }
        XCTAssertEqual(archive.remaining, 0)
        _ = archive.observe(midnight, calendar: calendar)
        XCTAssertEqual(archive.remaining, 2)
        XCTAssertTrue(archive.beginHand(key: "main", save: .init(match: Data()), license: .init(), at: midnight, calendar: calendar))
        _ = archive.observe(before, calendar: calendar)
        XCTAssertEqual(archive.remaining, 1)
        XCTAssertEqual(archive.lastSeen, midnight)
    }
    func testTrialAndPaidHandsDoNotConsumeFreeAllowance() {
        var archive = PlayArchive()
        for _ in 0..<4 {
            XCTAssertTrue(archive.beginHand(key: "main", save: .init(match: Data()), license: .init(trialStart: start), at: start, calendar: calendar))
        }
        XCTAssertEqual(archive.remaining, 2)
        _ = archive.beginHand(key: "main", save: .init(match: Data()), license: .init(lifetime: true), at: start, calendar: calendar)
        XCTAssertEqual(archive.remaining, 2)
        _ = archive.observe(start.addingTimeInterval(14 * 86_400), calendar: calendar)
        XCTAssertTrue(archive.beginHand(key: "main", save: .init(match: Data()), license: .init(trialStart: start), at: start.addingTimeInterval(14 * 86_400), calendar: calendar))
        XCTAssertEqual(archive.remaining, 1)
    }
    func testTravelWestDoesNotResetTheSameAllowance() {
        var archive = PlayArchive()
        let date = calendar.startOfDay(for: start).addingTimeInterval(3_600)
        _ = archive.beginHand(key: "main", save: .init(match: Data()), license: .init(), at: date, calendar: calendar)
        var west = calendar; west.timeZone = TimeZone(secondsFromGMT: -10 * 3_600)!
        _ = archive.observe(date, calendar: west)
        XCTAssertEqual(archive.remaining, 1)
    }
    func testDaylightSavingResetUsesCalendarMidnight() {
        var c = calendar; c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = c.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        var archive = PlayArchive()
        _ = archive.beginHand(key: "main", save: .init(match: Data()), license: .init(), at: date, calendar: c)
        _ = archive.observe(c.date(byAdding: .day, value: 1, to: date)!, calendar: c)
        XCTAssertEqual(archive.remaining, 2)
    }
    func testRestoringTrialCannotStartItAgain() {
        var archive = PlayArchive()
        archive.recordTrialStart(start)
        archive.recordTrialStart(start.addingTimeInterval(86_400))
        XCTAssertEqual(archive.firstTrialStart, start)
    }

    @MainActor func testMigrationResumesWithoutChargingAndNewHandPersistsWithAllowance() throws {
        let name = "FuzhouAccessTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("saved".utf8), forKey: "solo-match.v2")
        defaults.set([2, 1], forKey: "solo-match.v2.rack-order")
        let access = GameAccess(defaults: defaults, keychainService: nil, now: { self.start })
        XCTAssertEqual(access.remainingSoloHands, 2)
        XCTAssertEqual(access.soloSave(key: "solo-match.v2")?.rackOrder, [2, 1])
        XCTAssertTrue(access.beginSoloHand(key: "solo-match.second.v1", match: Data("new".utf8)))
        access.saveSolo(key: "solo-match.second.v1", match: Data("move".utf8), rackOrder: [4, 3])
        let reopened = GameAccess(defaults: defaults, keychainService: nil, now: { self.start })
        XCTAssertEqual(reopened.remainingSoloHands, 1)
        XCTAssertEqual(reopened.soloSave(key: "solo-match.second.v1")?.match, Data("move".utf8))
        XCTAssertEqual(reopened.soloSave(key: "solo-match.second.v1")?.rackOrder, [4, 3])
        XCTAssertFalse(reopened.authorizeHosting())
    }

    @MainActor func testRetainingAMigratedSavePreservesItsHandAndAllowance() throws {
        let name = "FuzhouAccessTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let access = GameAccess(defaults: defaults, keychainService: nil, now: { self.start })
        XCTAssertTrue(access.beginSoloHand(key: SoloSaveSlot.first.rawValue, match: Data("first".utf8)))
        XCTAssertTrue(access.beginSoloHand(key: SoloSaveSlot.second.rawValue, match: Data("second".utf8)))
        let selected = try XCTUnwrap(access.soloSave(key: SoloSaveSlot.second.rawValue))
        let remaining = access.remainingSoloHands
        let settled = Data("settled".utf8)
        XCTAssertTrue(access.retainSoloSave(.second, replacingWith: (match: settled, rackOrder: nil)))

        let reopened = GameAccess(defaults: defaults, keychainService: nil, now: { self.start })
        let retained = try XCTUnwrap(reopened.soloSave(key: SoloSaveSlot.first.rawValue))
        XCTAssertEqual(retained.match, settled)
        XCTAssertEqual(retained.handID, selected.handID)
        XCTAssertNil(reopened.soloSave(key: SoloSaveSlot.second.rawValue))
        XCTAssertEqual(reopened.remainingSoloHands, remaining)
    }
}
