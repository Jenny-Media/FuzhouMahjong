import XCTest
import FuzhouCore
import Network
@testable import FuzhouNearby

final class NearbyLoopbackTests: XCTestCase {
    @MainActor
    func testFreeGuestCanJoinHostButCannotCreateOrAdvanceItsOwnRoom() async throws {
        let host = NearbySession(loopback: true)
        let guest = NearbySession(loopback: true, hostingAllowed: { false })
        defer { host.leave(); guest.leave() }
        guest.create(name: "Free")
        XCTAssertFalse(guest.isHost)
        let houseRules = FuzhouHouseRules(name: "周末", keepDealerOnDraw: true, discardPayment: .allOpponents,
                                         flush: .disabled, goldIndicators: .includeWinds)
        host.create(name: "Paid", houseRules: houseRules)
        for _ in 0..<100 where host.loopbackRoom == nil { try await Task.sleep(for: .milliseconds(20)) }
        guest.join(try XCTUnwrap(host.loopbackRoom), name: "Free")
        for _ in 0..<100 where guest.players.count < 2 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(guest.players.count, 2)
        XCTAssertEqual(guest.update?.ruleset, .oldThree)
        XCTAssertEqual(guest.update?.houseRules, houseRules)
        XCTAssertFalse(guest.canAdvance)
        var random = FixtureRandom(seed: 341)
        host.startMatch(using: &random)
        for _ in 0..<100 where guest.table == nil { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(guest.table?.ruleset, .oldThree)
        XCTAssertEqual(guest.table?.houseRules, houseRules)
        let hostTable = try XCTUnwrap(host.table)
        let guestTable = try XCTUnwrap(guest.table)
        XCTAssertEqual(guestTable.players.map(\.exposedFlowers), hostTable.players.map(\.exposedFlowers))
        let exposed = guestTable.players.flatMap { $0.exposedFlowers ?? [] }
        XCTAssertFalse(exposed.isEmpty)
        XCTAssertTrue(exposed.allSatisfy { $0.kind.isFlower && !guestTable.isGold($0) })
    }

    @MainActor
    func testHostTrialExpiringBeforeStartCannotDealButRoomCanRemainOpen() async throws {
        var allowed = true
        let host = NearbySession(loopback: true, hostingAllowed: { allowed })
        let guest = NearbySession(loopback: true)
        defer { host.leave(); guest.leave() }
        host.create(name: "Trial")
        for _ in 0..<100 where host.loopbackRoom == nil { try await Task.sleep(for: .milliseconds(20)) }
        guest.join(try XCTUnwrap(host.loopbackRoom), name: "Guest")
        for _ in 0..<100 where host.players.count < 2 { try await Task.sleep(for: .milliseconds(20)) }
        allowed = false
        host.startMatch()
        XCTAssertTrue(host.isHost)
        XCTAssertNil(host.table)
        allowed = true
        host.startMatch()
        XCTAssertNotNil(host.table)
    }

    @MainActor
    func testDiscoveryResumesAfterForegroundOnlyWhileRequested() {
        let session = NearbySession(hostingAllowed: { false })
        defer { session.stopBrowsing() }
        session.browse()
        XCTAssertTrue(session.isBrowsing)
        session.setBackgrounded(true)
        XCTAssertFalse(session.isBrowsing)
        session.setBackgrounded(false)
        XCTAssertTrue(session.isBrowsing)

        session.stopBrowsing()
        session.setBackgrounded(true)
        session.setBackgrounded(false)
        XCTAssertFalse(session.isBrowsing)
    }

    @MainActor
    func testFreshGuestReturnsToTheSameSeatAndForgetsItOnDeparture() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let file = directory.appending(path: "seat.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = NearbySession(loopback: true)
        defer { host.leave() }
        host.create(name: "房主")
        try await until("host is ready") { host.loopbackRoom != nil }
        let room = try XCTUnwrap(host.loopbackRoom)

        var original: NearbySession? = NearbySession(loopback: true, seatFile: file, hostingAllowed: { false })
        original?.join(room, name: "小林")
        try await until("host accepted the saved seat") { original?.connected == true }
        host.startMatch()
        try await until("initial hand received") { original?.table != nil }
        let hand = try XCTUnwrap(original?.table)
        original?.setBackgrounded(true)
        try await until("host pauses for the absent guest") { host.paused }
        original?.setBackgrounded(false)
        XCTAssertEqual(original?.recovery, .reconnecting)
        original?.returnToLobby()
        XCTAssertFalse(original?.isInRoom == true)
        XCTAssertTrue(host.paused)
        original = nil

        let guest = NearbySession(loopback: true, seatFile: file, hostingAllowed: { false })
        XCTAssertEqual(guest.lastRoomName, "房主")
        guest.resumeLastRoom()
        XCTAssertEqual(guest.inviteSearch, .searching)
        let otherKey = DiscoveredRoom(id: room.id, name: room.name, endpoint: room.endpoint,
                                      publicKey: Data(repeating: 1, count: 32))
        guest.discoveredRoomsChanged([room.id: otherKey])
        XCTAssertFalse(guest.isInRoom)
        XCTAssertEqual(guest.lastRoomName, "房主")
        guest.discoveredRoomsChanged([:])
        guest.joinInvite(room.id, name: { "新昵称" })
        guest.discoveredRoomsChanged([room.id: room])
        try await until("original seat resumes without purchase") { guest.connected && !host.paused }
        XCTAssertEqual(guest.table, hand)
        XCTAssertNil(guest.openingRound)
        XCTAssertEqual(host.players.count, 2)
        XCTAssertEqual(guest.players.first(where: { $0.seat == hand.viewer })?.name, "小林")
        guest.leave()
        try await until("explicit exit releases the seat") { !guest.isInRoom && host.players.count == 1 }
        XCTAssertNil(NearbySession(loopback: true, seatFile: file).lastRoomName)
    }

    @MainActor
    func testGuestRestoresTheExactHandAfterInterruptionBeforeFirstReply() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let file = directory.appending(path: "seat.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = NearbySession(loopback: true)
        defer { host.leave() }
        host.create(name: "房主")
        try await until("host is ready") { host.loopbackRoom != nil }
        let room = try XCTUnwrap(host.loopbackRoom)
        let proxy = try MoveTimeoutProxy(target: room, blockFirstReply: true)
        defer { proxy.stop() }
        try await until("proxy is ready") { proxy.room != nil }
        var initial: NearbySession? = NearbySession(loopback: true, seatFile: file)
        initial?.join(try XCTUnwrap(proxy.room), name: "小林")
        try await until("host accepted guest without the reply") { host.canStart }
        XCTAssertFalse(initial?.connected == true)
        host.startMatch()
        initial?.setBackgrounded(true)
        proxy.stop()
        initial = nil
        try await until("host reserves the seat") { host.paused }
        let held = try XCTUnwrap(host.players.first { $0.name == "小林" }?.seat)
        let full = NearbySession(loopback: true), other = NearbySession(loopback: true)
        full.create(name: "已开局")
        defer { full.leave() }
        try await until("other table ready") { full.loopbackRoom != nil }
        let b = try XCTUnwrap(full.loopbackRoom)
        other.join(b, name: "另一位")
        try await until("other guest connected") { other.connected }
        full.startMatch()
        let fresh = NearbySession(loopback: true, seatFile: file)
        fresh.join(b, name: "小林")
        try await until("second host rejected the attempt") { !fresh.isInRoom }
        XCTAssertEqual(fresh.lastRoomName, "房主")
        fresh.resumeLastRoom()
        fresh.discoveredRoomsChanged([room.id: room])
        try await until("fresh session recovers outstanding join") { fresh.connected && !host.paused }
        XCTAssertEqual(fresh.table?.viewer, held)
        XCTAssertEqual(fresh.table?.hand.count, 16)
        let restored = try XCTUnwrap(fresh.table)
        fresh.setBackgrounded(true)
        try await until("host pauses again") { host.paused }
        fresh.setBackgrounded(false)
        fresh.returnToLobby()
        fresh.resumeLastRoom()
        fresh.discoveredRoomsChanged([room.id: room])
        try await until("same private snapshot") { fresh.connected && !host.paused }
        XCTAssertEqual(fresh.table, restored)
    }

    @MainActor
    func testExplicitLobbyChoicesSupersedeSavedSearchAndRejectionRetainsPriorSeat() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let file = directory.appending(path: "seat.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = NearbySession(loopback: true), second = NearbySession(loopback: true)
        first.create(name: "原桌")
        second.create(name: "扫码桌")
        defer { first.leave(); second.leave() }
        try await until("both tables ready") { first.loopbackRoom != nil && second.loopbackRoom != nil }
        let a = try XCTUnwrap(first.loopbackRoom), b = try XCTUnwrap(second.loopbackRoom)
        let original = NearbySession(loopback: true, seatFile: file)
        original.join(a, name: "牌友")
        try await until("original guest connected") { original.connected }
        let archive = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        // Install the previous app version's single-seat file ahead of relaunch.
        var legacy = try XCTUnwrap((archive["rooms"] as? [[String: Any]])?.first)
        legacy.removeValue(forKey: "confirmed")
        try JSONSerialization.data(withJSONObject: legacy).write(to: file)
        first.startMatch()
        try await until("original hand received") { original.table != nil }
        original.setBackgrounded(true)
        try await until("first host waits") { first.paused }
        let reopened = NearbySession(loopback: true, seatFile: file)
        reopened.resumeLastRoom()
        XCTAssertEqual(reopened.inviteSearch, .searching)
        reopened.cancelInviteSearch()
        reopened.discoveredRoomsChanged([a.id: a])
        XCTAssertFalse(reopened.isInRoom)
        reopened.create(name: "新桌")
        XCTAssertTrue(reopened.isHost)
        reopened.leave()

        reopened.discoveredRoomsChanged([:])
        reopened.resumeLastRoom()
        reopened.cancelInviteSearch()
        reopened.discoveredRoomsChanged([a.id: a, b.id: b])
        // Once B is in progress, a new guest should get the rejection from B.
        let other = NearbySession(loopback: true)
        other.join(b, name: "另一位")
        try await until("B can start") { second.canStart }
        second.startMatch()
        reopened.joinInvite(b.id, name: "牌友")
        try await until("B rejected new guest") { !reopened.isInRoom }
        XCTAssertEqual(reopened.notice, "牌桌已满或对局已开始。")
        let retry = NearbySession(loopback: true, seatFile: file)
        XCTAssertEqual(retry.lastRoomName, "原桌")
        retry.discoveredRoomsChanged([a.id: a])
        retry.resumeLastRoom()
        try await until("confirmed seat survived failed new join") { retry.connected && !first.paused }
    }

    @MainActor
    func testExplicitInviteWhileAutomaticJoinAwaitsHostKeepsBothSeats() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + "/seat.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let first = NearbySession(loopback: true), second = NearbySession(loopback: true)
        first.create(name: "原桌")
        second.create(name: "新桌")
        defer { first.leave(); second.leave() }
        try await until("both ready") { first.loopbackRoom != nil && second.loopbackRoom != nil }
        let a = try XCTUnwrap(first.loopbackRoom), b = try XCTUnwrap(second.loopbackRoom)
        let initial = NearbySession(loopback: true, seatFile: file)
        initial.join(a, name: "小林")
        try await until("initial guest seated") { initial.connected }
        first.startMatch()
        try await until("first hand received") { initial.table != nil }
        let original = try XCTUnwrap(initial.table)
        initial.setBackgrounded(true)
        try await until("first host paused") { first.paused }

        let guest = NearbySession(loopback: true, seatFile: file)
        guest.resumeLastRoom(automatically: true)
        guest.beginLobbyChoice() // Focusing the code field cancels a pending discovery.
        guest.discoveredRoomsChanged([a.id: a])
        XCTAssertFalse(guest.isInRoom)

        let proxy = try MoveTimeoutProxy(target: a, blockFirstReply: true)
        defer { proxy.stop() }
        try await until("proxy ready") { proxy.room != nil }
        guest.discoveredRoomsChanged([a.id: try XCTUnwrap(proxy.room), b.id: b])
        guest.resumeLastRoom(automatically: true)
        try await until("A accepted but its reply is held") { !first.paused }
        XCTAssertFalse(guest.connected)
        XCTAssertTrue(guest.automaticallyReturning)
        guest.joinInvite(b.id, name: "小林")
        try await until("explicit invite won") { guest.connected && guest.roomID == b.id }
        try await until("superseded link disconnected from A") { first.paused }
        XCTAssertEqual(guest.earlierRooms.map(\.id), [a.id])
        guest.joinInvite(a.id, name: "小林")
        XCTAssertEqual(guest.roomID, b.id) // A confirmed connection stays put.
        guest.leave()
        try await until("B confirmed departure") { !guest.isInRoom }
        let reopened = NearbySession(loopback: true, seatFile: file)
        XCTAssertEqual(reopened.lastRoomName, "原桌")
        reopened.discoveredRoomsChanged([a.id: a])
        reopened.resumeLastRoom()
        try await until("rejoined original hand") { reopened.connected && !first.paused }
        XCTAssertEqual(reopened.table, original)
    }

    @MainActor
    func testUnreadableAndCorruptSeatFilesSurviveRetryAndManualJoin() async throws {
        let fm = FileManager.default
        let file = fm.temporaryDirectory.appending(path: UUID().uuidString + "/seat.json")
        defer { try? fm.removeItem(at: file.deletingLastPathComponent()) }
        let host = NearbySession(loopback: true)
        host.create(name: "原桌")
        defer { host.leave() }
        try await until("host ready") { host.loopbackRoom != nil }
        let room = try XCTUnwrap(host.loopbackRoom)
        let original = NearbySession(loopback: true, seatFile: file)
        original.join(room, name: "牌友")
        try await until("seat saved") { original.connected }
        host.startMatch()
        try await until("hand dealt") { original.table != nil }
        let hand = try XCTUnwrap(original.table)
        let valid = try Data(contentsOf: file)
        original.setBackgrounded(true)
        try await until("seat reserved") { host.paused }

        for bytes in [Data("{".utf8), Data(#"{"unknown":true}"#.utf8)] {
            try bytes.write(to: file)
            let guest = NearbySession(loopback: true, seatFile: file)
            guest.join(room, name: "新名")
            guest.retrySeatStorage()
            XCTAssertNotNil(guest.seatStorageIssue)
            XCTAssertFalse(guest.isInRoom)
            XCTAssertEqual(try Data(contentsOf: file), bytes)
            try valid.write(to: file)
            guest.retrySeatStorage()
            XCTAssertNil(guest.seatStorageIssue)
            XCTAssertEqual(guest.lastRoomName, "原桌")
        }

        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        let retry = NearbySession(loopback: true, seatFile: file)
        XCTAssertNotNil(retry.seatStorageIssue)
        retry.join(room, name: "新名")
        XCTAssertFalse(retry.isInRoom)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        retry.join(room, name: "新名")
        try await until("manual join reuses recovered key") { retry.connected && !host.paused }
        XCTAssertNil(retry.seatStorageIssue)
        XCTAssertEqual(retry.table, hand)
        XCTAssertEqual(try Data(contentsOf: file), valid)
    }

    @MainActor
    func testLegacyConfirmedAndPendingRoomsMigrateTogether() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "seat.json")
        func legacy(_ name: String) -> [String: String] {
            ["roomID": UUID().uuidString, "hostName": name, "guestName": "牌友",
             "seatKey": UUID().uuidString, "hostKey": Data(repeating: 1, count: 32).base64EncodedString()]
        }
        let a = legacy("甲"), b = legacy("乙")
        try JSONEncoder().encode(["confirmed": a, "pending": b]).write(to: file)
        let guest = NearbySession(loopback: true, seatFile: file)
        XCTAssertNil(guest.seatStorageIssue)
        XCTAssertEqual(guest.lastRoomName, "乙")
        XCTAssertEqual(guest.earlierRooms.map(\.name), ["甲"])
        guest.forgetLastRoom()
        let migrated = NearbySession(loopback: true, seatFile: file)
        XCTAssertEqual(migrated.lastRoomName, "甲")
        let archive = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let rooms = try XCTUnwrap(archive["rooms"] as? [[String: Any]])
        XCTAssertEqual(rooms.first?["seatKey"] as? String, a["seatKey"])
        XCTAssertEqual(rooms.first?["hostKey"] as? String, a["hostKey"])
    }

    @MainActor
    func testLostLeaveConfirmationKeepsTheCredentialUntilTheHostResolvesIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let file = directory.appending(path: "seat.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = NearbySession(loopback: true), guest = NearbySession(loopback: true, seatFile: file)
        host.create(name: "房主")
        defer { host.leave() }
        try await until("room is ready") { host.loopbackRoom != nil }
        let room = try XCTUnwrap(host.loopbackRoom)
        let proxy = try MoveTimeoutProxy(target: room)
        defer { proxy.stop() }
        try await until("guest proxy is ready") { proxy.room != nil }
        guest.join(try XCTUnwrap(proxy.room), name: "牌友")
        try await until("guest seated") { guest.connected }
        host.startMatch()
        try await until("guest has active hand") { guest.table != nil }
        proxy.block(.hostToGuest)
        guest.leave()
        try await until("host released guest") { host.players.count == 1 }
        proxy.stop()
        try await until("unconfirmed exit returns to lobby") { !guest.isInRoom }
        XCTAssertNotNil(guest.notice)
        let fresh = NearbySession(loopback: true, seatFile: file)
        XCTAssertEqual(fresh.lastRoomName, "房主")
        fresh.discoveredRoomsChanged([room.id: room])
        fresh.resumeLastRoom()
        try await until("host confirms the seat is gone") { fresh.lastRoomName == nil }
        XCTAssertNil(NearbySession(loopback: true, seatFile: file).lastRoomName)
    }

    @MainActor
    func testSeatStorageFailuresStayVisibleAndCanBeRetried() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let file = directory.appending(path: "seat.json")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let host = NearbySession(loopback: true), guest = NearbySession(loopback: true, seatFile: file)
        try Data().write(to: directory) // The directory becomes unwritable after the initial read.
        defer { host.leave() }
        host.create(name: "房主")
        try await until("listener ready") { host.loopbackRoom != nil }
        let room = try XCTUnwrap(host.loopbackRoom)
        guest.join(room, name: "牌友")
        try await until("seat write failed before sending join") { guest.seatStorageIssue != nil }
        XCTAssertFalse(guest.isInRoom)
        XCTAssertFalse(host.canStart)
        try FileManager.default.removeItem(at: directory)
        guest.retrySeatStorage()
        XCTAssertNil(guest.seatStorageIssue)
        guest.join(room, name: "牌友")
        try await until("guest joined after storage recovered") { guest.connected }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        guest.leave()
        try await until("host confirms release") { !guest.isInRoom && !host.canStart }
        XCTAssertNotNil(guest.seatStorageIssue)
        XCTAssertNotNil(NearbySession(loopback: true, seatFile: file).lastRoomName)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        guest.retrySeatStorage()
        XCTAssertNil(guest.seatStorageIssue)
        XCTAssertNil(NearbySession(loopback: true, seatFile: file).lastRoomName)
    }

    @MainActor
    func testReturningGuestIsToldWhenTheHostHasReplacedTheirSeat() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let file = directory.appending(path: "seat.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = NearbySession(loopback: true)
        defer { host.leave() }
        host.create(name: "房主")
        try await until("host is ready") { host.loopbackRoom != nil }
        let room = try XCTUnwrap(host.loopbackRoom)
        let original = NearbySession(loopback: true, seatFile: file)
        original.join(room, name: "牌友")
        try await until("guest is seated") { original.connected }
        host.startMatch()
        try await until("guest receives a seat") { original.table != nil }
        let seat = try XCTUnwrap(original.table?.viewer)
        original.setBackgrounded(true)
        try await until("host can substitute") { host.paused }
        host.substitute(seat)
        let guest = NearbySession(loopback: true, seatFile: file)
        original.setBackgrounded(false)
        try await until("same guest receives the reason for losing its seat") { !original.isInRoom }
        XCTAssertTrue(original.notice?.contains("座位已释放") == true)
        guest.discoveredRoomsChanged([room.id: room])
        guest.resumeLastRoom()
        try await until("the original host rejected the released seat") { guest.lastRoomName == nil }
        XCTAssertFalse(guest.isInRoom)
        XCTAssertTrue(guest.notice?.contains("座位已释放") == true)
        XCTAssertNil(NearbySession(loopback: true, seatFile: file).lastRoomName)
    }

    @MainActor
    func testMissingInviteTimesOutAndCanRetryOrCancel() async throws {
        let session = NearbySession(loopback: true, inviteTimeout: .milliseconds(160))
        defer { session.stopBrowsing() }
        session.joinInvite(UUID(), name: "牌友")
        XCTAssertEqual(session.inviteSearch, .searching)
        try await until("missing invite reaches a bounded result") { session.inviteSearch == .unavailable }
        XCTAssertFalse(session.isInRoom)

        session.retryInviteSearch()
        XCTAssertEqual(session.inviteSearch, .searching)
        session.setBackgrounded(true)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(session.inviteSearch, .searching)
        session.setBackgrounded(false)
        try await until("invite search resumes its deadline") { session.inviteSearch == .unavailable }

        session.retryInviteSearch()
        session.cancelInviteSearch()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(session.inviteSearch)
        XCTAssertNil(session.notice)
    }

    @MainActor
    func testPendingInviteUsesLatestNicknameWhenHostAppears() async throws {
        let host = NearbySession(loopback: true), guest = NearbySession(loopback: true)
        defer { guest.leave(); host.leave() }
        host.create(name: "房主")
        try await until("host is ready") { host.loopbackRoom != nil }
        let room = try XCTUnwrap(host.loopbackRoom)

        let nickname = NicknamePreference()
        guest.joinInvite(room.id, name: { nickname.value })
        XCTAssertEqual(guest.inviteSearch, .searching)
        nickname.value = "新昵称"
        guest.discoveredRoomsChanged([room.id: room])
        try await until("guest joins when the host is discovered") { guest.connected }
        XCTAssertEqual(host.players.first(where: { $0.seat != .east })?.name, "新昵称")
    }

    @MainActor
    func testInviteWaitsForNicknameSaveWhileHostIsAvailable() async throws {
        let host = NearbySession(loopback: true)
        let guest = NearbySession(loopback: true, inviteTimeout: .milliseconds(160))
        defer { guest.leave(); host.leave() }
        host.create(name: "房主")
        try await until("host is ready") { host.loopbackRoom != nil }
        let room = try XCTUnwrap(host.loopbackRoom)
        let nickname = NicknamePreference()

        guest.joinInvite(room.id, name: { nickname.value })
        guest.setInviteJoiningDeferred(true)
        guest.discoveredRoomsChanged([room.id: room])
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(guest.inviteSearch, .searching)
        XCTAssertFalse(guest.isInRoom)

        nickname.value = "新昵称"
        guest.setInviteJoiningDeferred(false)
        try await until("guest joins after saving their nickname") { guest.connected }
        XCTAssertEqual(host.players.first(where: { $0.seat != .east })?.name, "新昵称")
    }

    @MainActor
    func testCancelingNicknameEditWaitsForHostToReappear() async throws {
        let host = NearbySession(loopback: true), guest = NearbySession(loopback: true)
        defer { guest.leave(); host.leave() }
        host.create(name: "房主")
        try await until("host is ready") { host.loopbackRoom != nil }
        let room = try XCTUnwrap(host.loopbackRoom)
        let nickname = NicknamePreference()

        guest.discoveredRoomsChanged([room.id: room])
        guest.setInviteJoiningDeferred(true)
        guest.joinInvite(room.id, name: { nickname.value })
        XCTAssertFalse(guest.isInRoom)
        guest.discoveredRoomsChanged([:])
        guest.setInviteJoiningDeferred(false)
        XCTAssertFalse(guest.isInRoom)
        XCTAssertEqual(guest.inviteSearch, .searching)

        guest.discoveredRoomsChanged([room.id: room])
        try await until("guest joins when the host returns") { guest.connected }
        XCTAssertEqual(host.players.first(where: { $0.seat != .east })?.name, "旧昵称")
    }

    @MainActor
    func testInviteRetryUsesLatestNicknameAfterSearchTimeout() async throws {
        let host = NearbySession(loopback: true)
        let guest = NearbySession(loopback: true, inviteTimeout: .milliseconds(160))
        defer { guest.leave(); host.leave() }
        host.create(name: "房主")
        try await until("host is ready") { host.loopbackRoom != nil }
        let room = try XCTUnwrap(host.loopbackRoom)

        let nickname = NicknamePreference()
        guest.joinInvite(room.id, name: { nickname.value })
        try await until("missing invite reaches a bounded result") { guest.inviteSearch == .unavailable }
        nickname.value = "新昵称"
        guest.discoveredRoomsChanged([room.id: room])
        XCTAssertFalse(guest.isInRoom)
        guest.retryInviteSearch()
        try await until("guest joins after retrying the invite") { guest.connected }
        XCTAssertEqual(host.players.first(where: { $0.seat != .east })?.name, "新昵称")
    }

    @MainActor
    func testBonjourRoomLabelFitsWhenRosterNameContainsLongEmoji() async throws {
        let host = NearbySession(loopback: true), guest = NearbySession(loopback: true)
        defer { guest.leave(); host.leave() }
        let family = "👨‍👩‍👧‍👦"
        let fullName = String(repeating: family, count: 12)
        host.create(name: fullName)
        try await until("host is ready") { host.loopbackRoom != nil }
        let room = try XCTUnwrap(host.loopbackRoom)

        let txt = NearbySession.roomTXTRecord(id: room.id, name: room.name, publicKey: room.publicKey)
        let label = try XCTUnwrap(txt["name"])
        XCTAssertEqual(label, String(repeating: family, count: 9))
        XCTAssertEqual(txt["id"], room.id.uuidString)
        XCTAssertEqual(txt["key"], room.publicKey.base64EncodedString())

        let oversizedCharacter = "a" + String(repeating: "\u{0301}", count: 120)
        XCTAssertEqual(oversizedCharacter.count, 1)
        let fallback = NearbySession.roomTXTRecord(id: room.id, name: oversizedCharacter, publicKey: room.publicKey)
        XCTAssertEqual(fallback["name"], "牌友")

        let advertisedRoom = DiscoveredRoom(id: room.id, name: label, endpoint: room.endpoint, publicKey: room.publicKey)
        guest.join(advertisedRoom, name: "牌友")
        try await until("guest joins the advertised room") { guest.connected }
        XCTAssertEqual(guest.players.first(where: { $0.seat == .east })?.name, fullName)
    }

    @MainActor
    func testHostedComputersProgressWithoutAViewAndPauseForAnOfflineGuest() async throws {
        let host = NearbySession(loopback: true)
        let guest = NearbySession(loopback: true)
        defer { guest.leave(); host.leave() }
        host.create(name: "房主")
        try await until("listener ready") { host.loopbackRoom != nil }
        guest.join(try XCTUnwrap(host.loopbackRoom), name: "牌友")
        try await until("guest joined") { guest.connected }
        host.startMatch()
        try await until("guest receives the hand") { guest.table != nil }
        host.finishOpening(1)
        guest.finishOpening(1)
        XCTAssertTrue(host.managesComputerTurns)

        for _ in 0..<20 {
            let revision = try XCTUnwrap(host.update?.revision)
            try await until("guest is up to date") { guest.update?.revision == revision }
            if host.computerHasMove {
                guest.setBackgrounded(true)
                try await until("offline guest pauses the host") { host.paused }
                let pausedTable = host.table
                try await Task.sleep(for: .milliseconds(1500))
                XCTAssertEqual(host.table, pausedTable)
                guest.setBackgrounded(false)
                try await until("guest reconnects") { guest.connected && !host.paused }
                let resumedRevision = host.update?.revision
                try await until("computer acts without a MatchView") { host.update?.revision != resumedRevision }
                return
            }
            let actor = try XCTUnwrap([host, guest].first { $0.table?.moves.isEmpty == false })
            let moves = try XCTUnwrap(actor.table?.moves)
            let move = moves.contains(.pass) ? Move.pass : try XCTUnwrap(moves.last)
            XCTAssertTrue(actor.submit(move))
            try await until("human action accepted") { host.update?.revision != revision }
        }
        XCTFail("No computer response reached")
    }

    @MainActor
    func testFourClientsPlayAndReconnectAcrossRealEncryptedSockets() async throws {
        let host = NearbySession(loopback: true)
        let guests = (0..<3).map { _ in NearbySession(loopback: true) }
        defer {
            guests.forEach { $0.setBackgrounded(true); $0.leave() }
            host.leave()
        }

        host.create(name: "阿榕", ruleset: .oldThree)
        try await until("loopback listener ready") { host.loopbackRoom != nil }
        let room = try XCTUnwrap(host.loopbackRoom)
        for (index, guest) in guests.enumerated() {
            guest.join(room, name: "Guest \(index + 1)")
            try await until("guest joined") { guest.connected }
        }
        XCTAssertTrue(host.canStart)
        host.startMatch()
        try await until("all seats receive a table") { guests.allSatisfy { $0.table != nil } }

        let clients = [host] + guests
        let states = try clients.map { try XCTUnwrap($0.table) }
        XCTAssertTrue(states.allSatisfy { $0.ruleset == .oldThree && $0.houseRules == nil })
        XCTAssertTrue(clients.allSatisfy { $0.openingRound == 1 })
        guests[0].finishOpening(1)
        XCTAssertNil(guests[0].openingRound)
        XCTAssertTrue(([host] + guests.dropFirst()).allSatisfy { $0.openingRound == 1 })
        let reconnectingDuringDeal = guests[2]
        reconnectingDuringDeal.setBackgrounded(true)
        try await until("host pauses during the opening deal") { host.paused }
        reconnectingDuringDeal.setBackgrounded(false)
        try await until("guest returns during the opening deal") {
            reconnectingDuringDeal.connected && !host.paused
        }
        XCTAssertEqual(reconnectingDuringDeal.table, states[3])
        XCTAssertNil(reconnectingDuringDeal.openingRound)
        clients.forEach { $0.finishOpening(1) }
        XCTAssertEqual(Set(states.map(\.viewer)), Set(Seat.allCases))
        let privateIDs = states.flatMap { $0.hand.map(\.id) }
        XCTAssertEqual(Set(privateIDs).count, 64)

        // Decline opening Rob Gold offers so the dealer can make a regular discard.
        for client in clients where client.table?.step == .opening && client.table?.moves.contains(.pass) == true {
            XCTAssertTrue(client.submit(.pass))
        }
        try await until("dealer can discard") { host.table?.step == .turn }
        let openingDraw = try XCTUnwrap(host.table?.lastDraw)
        try await until("all clients see the draw source without seeing the drawn tile") {
            guests.allSatisfy { $0.table?.lastDraw == openingDraw && $0.table?.drawn == nil }
        }
        let discard = try XCTUnwrap(host.table?.moves.first { if case .discard = $0 { true } else { false } })
        guard case .discard(let id) = discard else { return XCTFail("expected a discard") }
        XCTAssertTrue(host.submit(discard))
        try await until("discard reaches all four seats") {
            clients.allSatisfy { $0.table?.latestDiscard?.id == id && $0.table?.latestDiscard?.seat == .east }
        }

        let returning = guests[1]
        let previous = try XCTUnwrap(returning.table)
        returning.setBackgrounded(true)
        try await until("host pauses while a guest is offline") { host.paused }
        returning.setBackgrounded(false)
        try await until("guest rejoins the same active game") { returning.connected && !host.paused }
        XCTAssertEqual(returning.table, previous)
        XCTAssertTrue(clients.allSatisfy { $0.openingRound == nil })

        for _ in 0..<250 where host.table?.result == nil {
            let revision = try XCTUnwrap(host.update?.revision)
            try await until("clients see the current revision") {
                clients.allSatisfy { $0.update?.revision == revision }
            }
            let actor = try XCTUnwrap(clients.first { $0.table?.moves.isEmpty == false })
            let before = try XCTUnwrap(actor.table)
            let moves = before.moves
            let move = moves.contains(.win) ? Move.win : moves.contains(.pass) ? .pass : try XCTUnwrap(moves.last)
            XCTAssertTrue(actor.submit(move))
            if actor !== host { XCTAssertEqual(actor.moveStatus, .sending) }
            XCTAssertFalse(actor.submit(move))
            try await until("host accepts a legal move") { host.update?.revision != revision }
            let after = try XCTUnwrap(host.table)
            let waitsForAnotherPlayer = moves.contains(.pass) && after.step == before.step &&
                after.roundNumber == before.roundNumber && after.current == before.current && after.offeredTile == before.offeredTile
            let resolvedRevision = try XCTUnwrap(host.update?.revision)
            if waitsForAnotherPlayer {
                try await until("receipt arrives while other players can still respond") {
                    actor.update?.revision == resolvedRevision && actor.moveStatus == .waitingForResolution
                }
                XCTAssertFalse(actor.submit(move))
            } else {
                try await until("completed move unlocks the controls") {
                    actor.update?.revision == resolvedRevision && actor.moveStatus == nil
                }
            }
        }
        let result = try XCTUnwrap(host.table?.result)
        try await until("the same final settlement reaches all four clients") {
            clients.allSatisfy { $0.table?.result == result }
        }
        XCTAssertTrue(clients.allSatisfy { $0.moveStatus == nil })
        XCTAssertEqual(Seat.allCases.map(result.delta).reduce(0, +), 0)
        guests[0].nextHand()
        XCTAssertEqual(host.table?.result, result)
        host.nextHand()
        try await until("all four clients advance to the next hand") {
            clients.allSatisfy { $0.table?.roundNumber == 2 && $0.table?.result == nil }
        }
        XCTAssertEqual(host.openingRound, 2)
        XCTAssertTrue(guests.allSatisfy { $0.openingRound == nil })

        returning.leave()
        try await until("intentional departure releases the seat") {
            !returning.isInRoom && host.players.count == 3 && !host.paused
        }
        host.leave()
        try await until("the host ending the table dismisses the other guests") {
            guests.allSatisfy { !$0.isInRoom }
        }
    }

    @MainActor
    func testGuestGetsPrivateFeedbackWhenWinSettlesBeforeChowArrives() async throws {
        try await assertLateChowFeedback(seed: 341, firstDiscard: true, moves: 2, claimant: .north, winner: .win)
    }

    @MainActor
    func testGuestGetsPrivateFeedbackWhenPungSettlesBeforeChowArrives() async throws {
        try await assertLateChowFeedback(seed: 3, firstDiscard: false, moves: 49,
                                         claimant: .west, winner: .meld(.pung, [52, 54]))
    }

    @MainActor
    private func assertLateChowFeedback(seed: UInt64, firstDiscard: Bool, moves: Int,
                                       claimant seat: Seat, winner: Move) async throws {
        let host = NearbySession(loopback: true)
        let guests = (0..<3).map { _ in NearbySession(loopback: true) }
        let clients = [host] + guests
        defer { host.leave(); guests.forEach { $0.setBackgrounded(true); $0.leave() } }
        host.create(name: "Host", ruleset: .oldThree)
        try await until("host listens") { host.loopbackRoom != nil }
        let room = try XCTUnwrap(host.loopbackRoom)
        for guest in guests {
            guest.join(room, name: "Guest")
            try await until("guest joins") { guest.connected }
        }

        var random = FixtureRandom(seed: seed)
        host.startMatch(using: &random)
        try await until("all seats receive the deal") { clients.allSatisfy { $0.table != nil } }
        clients.forEach { $0.finishOpening(1) }
        func play(_ move: Move, by actor: NearbySession) async throws {
            let revision = try XCTUnwrap(host.update?.revision)
            XCTAssertTrue(actor.submit(move))
            try await until("all clients receive the next move") {
                host.update?.revision != revision && clients.allSatisfy { $0.update?.revision == host.update?.revision }
            }
        }
        if firstDiscard {
            let move = try XCTUnwrap(host.table?.moves.first { if case .discard = $0 { true } else { false } })
            try await play(move, by: host)
        }
        for _ in 0..<moves {
            let actor = try XCTUnwrap(clients.first { $0.table?.moves.isEmpty == false })
            let moves = try XCTUnwrap(actor.table?.moves)
            let move = moves.contains(.win) ? .win : moves.contains(.pass) ? .pass : try XCTUnwrap(moves.last)
            try await play(move, by: actor)
        }

        let claimant = clients[seat.id]
        let offered = try XCTUnwrap(claimant.table)
        let chow = try XCTUnwrap(offered.moves.first { if case .meld(.chow, _) = $0 { true } else { false } })
        XCTAssertEqual(offered.viewer, seat)
        XCTAssertEqual(offered.offeredTile, host.table?.offeredTile)
        XCTAssertTrue(host.submit(winner))
        XCTAssertEqual(host.table?.step, winner == .win ? .finished : .turn)
        // Both calls are synchronous. The guest can still tap the offer before the host update arrives.
        XCTAssertEqual(claimant.table, offered)
        XCTAssertTrue(claimant.submit(chow))
        XCTAssertEqual(claimant.moveStatus, .sending)
        try await until("late move receipt arrives") { claimant.update?.moveReceipt?.accepted == false }
        XCTAssertNil(claimant.moveStatus)
        XCTAssertEqual(claimant.table?.discardClaimFeedback, .overridden(chow, by: winner))
        XCTAssertTrue(clients.filter { $0 !== claimant }.allSatisfy { $0.table?.discardClaimFeedback == nil })

        if winner == .win {
            XCTAssertEqual(host.table?.result?.winner, .east)
            host.nextHand()
            try await until("claimant opens the next hand") { claimant.table?.roundNumber == 2 }
        } else {
            let next = try XCTUnwrap(host.table?.moves.first { if case .discard = $0 { true } else { false } })
            try await play(next, by: host)
        }
        XCTAssertNil(claimant.table?.discardClaimFeedback)
    }

    @MainActor
    func testTimedOutGuestWaitsForFreshTableBeforeSubmittingAgain() async throws {
        let host = NearbySession(loopback: true)
        let guest = NearbySession(loopback: true, moveReplyTimeout: .milliseconds(400))
        let others = (0..<2).map { _ in NearbySession(loopback: true) }
        let clients = [host, guest] + others
        host.create(name: "Host")
        try await until("host listens") { host.loopbackRoom != nil }
        let room = try XCTUnwrap(host.loopbackRoom)
        let proxy = try MoveTimeoutProxy(target: room)
        defer {
            for guest in clients.dropFirst() { guest.setBackgrounded(true); guest.leave() }
            host.leave()
            proxy.stop()
        }

        try await until("proxy listens") { proxy.room != nil }
        guest.join(try XCTUnwrap(proxy.room), name: "Guest")
        try await until("proxied guest joins") { guest.connected }
        for other in others {
            other.join(room, name: "Other")
            try await until("other guest joins") { other.connected }
        }
        host.startMatch()
        try await until("all seats have a table") { clients.allSatisfy { $0.table != nil } }
        clients.forEach { $0.finishOpening(1) }

        // Pass opening and discard claims until the first guest draws.
        for _ in 0..<10 {
            let revision = try XCTUnwrap(host.update?.revision)
            try await until("all seats see the latest revision") { clients.allSatisfy { $0.update?.revision == revision } }
            if guest.table?.step == .turn, guest.table?.current == guest.table?.viewer { break }
            let actor = try XCTUnwrap(clients.first { $0.table?.moves.isEmpty == false })
            let moves = try XCTUnwrap(actor.table?.moves)
            let move = moves.contains(.pass) ? Move.pass : try XCTUnwrap(moves.first { if case .discard = $0 { true } else { false } })
            XCTAssertTrue(actor.submit(move))
            try await until("host applies the move") { host.update?.revision != revision }
        }
        let turn = try XCTUnwrap(guest.table)
        XCTAssertEqual(turn.step, .turn)
        XCTAssertEqual(turn.current, turn.viewer)
        let discards = turn.moves.compactMap { if case .discard(let id) = $0 { id } else { nil } }
        let first = Move.discard(try XCTUnwrap(discards.first))
        let alternative = Move.discard(try XCTUnwrap(discards.dropFirst().first))

        proxy.block(.guestToHost)
        XCTAssertTrue(guest.submit(first))
        try await until("missing request triggers reconnect") { guest.recovery == .reconnecting }
        XCTAssertEqual(guest.moveStatus, .sending)
        XCTAssertFalse(guest.submit(alternative))
        try await until("fresh table restores the same move") { guest.connected && guest.moveStatus == nil }
        XCTAssertEqual(guest.table, turn)

        proxy.block(.hostToGuest)
        XCTAssertTrue(guest.submit(first))
        try await until("host records the discard before the guest receives a reply") {
            host.table?.latestDiscard?.id == discards.first
        }
        XCTAssertFalse(guest.submit(alternative))
        try await until("missing receipt triggers reconnect") { guest.recovery == .reconnecting }
        XCTAssertEqual(guest.moveStatus, .sending)
        XCTAssertFalse(guest.submit(alternative))
        try await until("fresh table shows the committed move") { guest.connected && guest.moveStatus == nil }
        XCTAssertEqual(guest.table?.latestDiscard, host.table?.latestDiscard)
        XCTAssertFalse(guest.submit(alternative))
    }

    @MainActor
    func testOfflineGuestCanEscapeAClosedRoomAfterBoundedRecovery() async throws {
        let host = NearbySession(loopback: true)
        let guest = NearbySession(loopback: true, recoveryTimeout: .milliseconds(1400))
        defer { guest.leave(); host.leave() }
        host.create(name: "房主")
        try await until("loopback listener ready") { host.loopbackRoom != nil }
        guest.join(try XCTUnwrap(host.loopbackRoom), name: "牌友")
        try await until("guest joined") { guest.connected }
        host.startMatch()
        try await until("guest sees the table") { guest.table != nil }

        guest.setBackgrounded(true)
        try await until("host sees disconnected guest") { host.paused }
        host.leave()
        guest.setBackgrounded(false)
        XCTAssertEqual(guest.recovery, .reconnecting)
        try await until("automatic reconnect stops") { guest.recovery == .unavailable }
        XCTAssertFalse(guest.connected)
        XCTAssertTrue(guest.paused)

        guest.retryRecovery()
        XCTAssertEqual(guest.recovery, .reconnecting)
        guest.leave()
        XCTAssertFalse(guest.isInRoom)
        XCTAssertNil(guest.table)
        XCTAssertNil(guest.recovery)
    }

    @MainActor
    private func until(_ reason: String, _ condition: () -> Bool) async throws {
        let max = ContinuousClock.now + .seconds(10)
        while !condition() && ContinuousClock.now < max {
            try await Task.sleep(for: .milliseconds(30))
        }
        guard condition() else { throw Failure.timeout(reason) }
    }

    @MainActor
    private final class NicknamePreference {
        var value = "旧昵称"
    }

    private enum Failure: Error { case timeout(String) }

    private struct FixtureRandom: RandomNumberGenerator {
        var seed: UInt64

        mutating func next() -> UInt64 {
            seed &+= 0x9E3779B97F4A7C15
            var value = seed
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            return value ^ (value >> 31)
        }
    }
}

/// Drops one direction on the current link while allowing the replacement link to resync normally.
@MainActor
private final class MoveTimeoutProxy {
    enum Direction { case guestToHost, hostToGuest }

    private let listener: NWListener
    private let target: DiscoveredRoom
    private var links: [UUID: (guest: NearbyWire, host: NearbyWire)] = [:]
    private var currentLink: UUID?
    private var blocked: (id: UUID, direction: Direction)?

    private var blockFirstReply: Bool

    init(target: DiscoveredRoom, blockFirstReply: Bool = false) throws {
        self.blockFirstReply = blockFirstReply
        self.target = target
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.forward(connection) }
        }
        listener.start(queue: .main)
    }

    var room: DiscoveredRoom? {
        guard let port = listener.port, port != .any else { return nil }
        return DiscoveredRoom(id: target.id, name: target.name, endpoint: .hostPort(host: "127.0.0.1", port: port),
                              publicKey: target.publicKey)
    }

    func block(_ direction: Direction) {
        blocked = currentLink.map { ($0, direction) }
    }

    private func forward(_ connection: NWConnection) {
        let guest = NearbyWire(connection)
        let host = NearbyWire(NWConnection(to: target.endpoint, using: .tcp))
        let id = guest.id
        currentLink = id
        if blockFirstReply {
            block(.hostToGuest)
            blockFirstReply = false
        }
        links[id] = (guest, host)
        guest.opened = { $0.accepted() }
        host.opened = { $0.accepted() }
        guest.received = { [weak self, weak host] _, frame in
            if self?.isBlocked(id, direction: .guestToHost) == false { host?.send(frame) }
        }
        host.received = { [weak self, weak guest] _, frame in
            if self?.isBlocked(id, direction: .hostToGuest) == false { guest?.send(frame) }
        }
        guest.ended = { [weak self] _ in
            self?.links.removeValue(forKey: id)?.host.close()
        }
        host.ended = { [weak guest] _ in guest?.close() }
        host.start()
        guest.start()
    }

    private func isBlocked(_ id: UUID, direction: Direction) -> Bool {
        blocked?.id == id && blocked?.direction == direction
    }

    func stop() {
        listener.cancel()
        for link in Array(links.values) { link.guest.close(); link.host.close() }
    }
}
