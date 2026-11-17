import XCTest
import FuzhouCore
@testable import FuzhouNearby

final class NearbyLoopbackTests: XCTestCase {
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
    private func until(_ reason: String, _ condition: () -> Bool) async throws {
        let max = ContinuousClock.now + .seconds(10)
        while !condition() && ContinuousClock.now < max {
            try await Task.sleep(for: .milliseconds(30))
        }
        guard condition() else { throw Failure.timeout(reason) }
    }

    private enum Failure: Error { case timeout(String) }
}
