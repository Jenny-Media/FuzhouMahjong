import XCTest
import FuzhouCore
@testable import FuzhouNearby

final class NearbyLoopbackTests: XCTestCase {
    @MainActor
    func testFreeGuestCanJoinHostButCannotCreateOrAdvanceItsOwnRoom() async throws {
        let host = NearbySession(loopback: true)
        let guest = NearbySession(loopback: true, hostingAllowed: { false })
        defer { host.leave(); guest.leave() }
        guest.create(name: "Free")
        XCTAssertFalse(guest.isHost)
        host.create(name: "Paid")
        for _ in 0..<100 where host.loopbackRoom == nil { try await Task.sleep(for: .milliseconds(20)) }
        guest.join(try XCTUnwrap(host.loopbackRoom), name: "Free")
        for _ in 0..<100 where guest.players.count < 2 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(guest.players.count, 2)
        XCTAssertFalse(guest.canAdvance)
        host.startMatch()
        for _ in 0..<100 where guest.table == nil { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNotNil(guest.table)
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

        host.create(name: "阿榕")
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
        XCTAssertTrue(clients.allSatisfy { $0.openingRound == 1 })
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
            let moves = try XCTUnwrap(actor.table?.moves)
            let move = moves.contains(.win) ? Move.win : moves.contains(.pass) ? .pass : try XCTUnwrap(moves.last)
            XCTAssertTrue(actor.submit(move))
            try await until("host accepts a legal move") { host.update?.revision != revision }
        }
        let result = try XCTUnwrap(host.table?.result)
        try await until("the same final settlement reaches all four clients") {
            clients.allSatisfy { $0.table?.result == result }
        }
        XCTAssertEqual(Seat.allCases.map(result.delta).reduce(0, +), 0)
        host.nextHand()
        try await until("all four clients advance to the next hand") {
            clients.allSatisfy { $0.table?.roundNumber == 2 && $0.table?.result == nil && $0.openingRound == 2 }
        }

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

    private enum Failure: Error { case timeout(String) }
}
