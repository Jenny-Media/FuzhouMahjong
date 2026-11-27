import CryptoKit
import Foundation
import FuzhouCore
import Network
import Observation

public struct DiscoveredRoom: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    let endpoint: NWEndpoint
    let publicKey: Data

    public var code: String { String(id.uuidString.prefix(4)) }
}

@MainActor
@Observable
public final class NearbySession: MatchSession {
    public enum Recovery: Equatable, Sendable { case reconnecting, unavailable }
    public enum InviteSearch: Equatable, Sendable { case searching, unavailable }

    static let service = "_fuzhou._tcp"
    private let advertises: Bool
    private let recoveryTimeout: Duration
    private let inviteTimeout: Duration
    private let moveReplyTimeout: Duration

    private struct GuestSeat: Codable, Equatable {
        let roomID: UUID
        let hostKey: Data
        let hostName: String
        let seatKey: UUID
        let guestName: String
        var confirmed: Bool? = false // Absent in the two legacy file layouts.
        var acceptsHandReview: Bool? = nil
    }

    private struct PendingInvite {
        let roomID: UUID
        let name: @MainActor () -> String
    }

    private struct SeatArchive: Codable {
        let version: Int
        let rooms: [GuestSeat] // Most recently selected last.

        private enum Keys: String, CodingKey { case version, rooms, roomID, confirmed, pending }

        init(_ rooms: [GuestSeat]) {
            version = 1
            self.rooms = rooms
        }

        init(from decoder: Decoder) throws {
            let fields = try decoder.container(keyedBy: Keys.self)
            if fields.contains(.version) || fields.contains(.rooms) {
                version = try fields.decode(Int.self, forKey: .version)
                rooms = try fields.decode([GuestSeat].self, forKey: .rooms)
            } else {
                // Before multiple rooms, the file held a single seat or a confirmed/pending pair.
                version = 1
                if fields.contains(.roomID) {
                    var seat = try GuestSeat(from: decoder)
                    seat.confirmed = true
                    rooms = [seat]
                } else if fields.contains(.confirmed) || fields.contains(.pending) {
                    var confirmed = try fields.decodeIfPresent(GuestSeat.self, forKey: .confirmed)
                    var pending = try fields.decodeIfPresent(GuestSeat.self, forKey: .pending)
                    confirmed?.confirmed = true
                    pending?.confirmed = false
                    rooms = [confirmed, pending].compactMap { $0 }
                } else {
                    throw CocoaError(.fileReadCorruptFile)
                }
            }
            guard version == 1, !rooms.isEmpty, Set(rooms.map(\.roomID)).count == rooms.count,
                  rooms.allSatisfy({ $0.hostKey.count == 32 && $0.confirmed != nil }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
    }

    private let seatFile: URL?
    private var seats: [GuestSeat] = []
    private var needsSeatRead = false
    public private(set) var automaticallyReturning = false
    public var earlierRooms: [(id: UUID, name: String)] {
        seats.dropLast().reversed().map { ($0.roomID, $0.hostName) }
    }

    private func seat(in room: UUID) -> GuestSeat? { seats.first { $0.roomID == room } }
    private var returningToSeat = false
    public private(set) var seatStorageIssue: String?
    public var lastRoomName: String? { seats.last?.hostName }

    @ObservationIgnored private let hostingAllowed: @MainActor () -> Bool

    public convenience init(hostingAllowed: @escaping @MainActor () -> Bool) {
        let file = URL.applicationSupportDirectory.appending(path: "FuzhouMahjong/Nearby/guest-seat.json")
        self.init(loopback: false, seatFile: file, hostingAllowed: hostingAllowed)
    }

    init(loopback: Bool, recoveryTimeout: Duration = .seconds(15), inviteTimeout: Duration = .seconds(15),
         moveReplyTimeout: Duration = .seconds(4), seatFile: URL? = nil,
         hostingAllowed: @escaping @MainActor () -> Bool = { true }) {
        self.hostingAllowed = hostingAllowed
        self.seatFile = seatFile
        advertises = !loopback
        self.recoveryTimeout = recoveryTimeout
        self.inviteTimeout = inviteTimeout
        self.moveReplyTimeout = moveReplyTimeout
        readSeats()
    }

    @discardableResult
    private func readSeats() -> Bool {
        guard let seatFile else { return true }
        do {
            seats = try JSONDecoder().decode(SeatArchive.self, from: Data(contentsOf: seatFile)).rooms
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            seats = []
        } catch {
            needsSeatRead = true
            seatStorageIssue = "暂时无法读取已保存的座位。请重试后再加入牌桌。"
            return false
        }
        needsSeatRead = false
        seatStorageIssue = nil
        return true
    }

    var loopbackRoom: DiscoveredRoom? {
        guard !advertises, let host, let port = listener?.port, port != .any else { return nil }
        return DiscoveredRoom(id: host.id, name: host.name, endpoint: .hostPort(host: "127.0.0.1", port: port),
                              publicKey: host.agreementKey.publicKey.rawRepresentation)
    }

    private enum GuestMessage: Codable {
        case join(UUID, String, supportsHandReview: Bool?, acceptsHandReview: Bool?)
        case move(Move, Int, id: UUID?)
        case leave
    }

    private enum HostMessage: Codable {
        case update(RoomUpdate)
        case handReviewConfirmationRequired
        case rejected
        case closed
    }

    private struct Link {
        let wire: NearbyWire
        var cipher: NearbyCipher?
        var seat: Seat?
    }

    private struct HostedRoom {
        let id = UUID()
        let agreementKey = Curve25519.KeyAgreement.PrivateKey()
        let name: String
        var match: NearbyMatch
    }

    private struct ResponseWindow: Equatable {
        let round: Int
        let step: TableState.Step
        let current: Seat
        let tile: Tile?

        init?(_ table: TableState?) {
            guard let table, table.step == .claim || table.step == .opening else { return nil }
            round = table.roundNumber
            step = table.step
            current = table.current
            tile = table.offeredTile
        }

        func matchesSettledDiscard(in table: TableState) -> Bool {
            guard step == .claim, let tile, table.roundNumber == round,
                  table.step == .turn || table.step == .finished else { return false }
            return table.latestDiscard == TableDiscard(seat: current, tile: tile)
        }

        func overridingMove(in table: TableState) -> Move? {
            guard let tile, matchesSettledDiscard(in: table) else { return nil }
            if let result = table.result, result.kind == .discard, result.winningTile == tile,
               let winner = result.winner, winner != table.viewer { return .win }
            for player in table.players where player.seat != table.viewer {
                if let meld = player.melds.first(where: { $0.from == current && $0.tiles.contains(tile) }) {
                    return .meld(meld.kind, meld.tiles.filter { $0 != tile }.map(\.id).sorted())
                }
            }
            return nil
        }
    }

    private struct Submission {
        let id = UUID()
        let move: Move
        let revision: Int
        let window: ResponseWindow?
        var acknowledged = false
    }

    private var browser: NWBrowser?
    private var listener: NWListener?
    private var host: HostedRoom?
    private var links: [UUID: Link] = [:]
    private var guest: Link?
    private var target: DiscoveredRoom?
    private var seatKey = UUID()
    private var guestName = ""
    private var pendingInvite: PendingInvite?
    private var inviteJoiningDeferred = false
    private var retry: Task<Void, Never>?
    private var recoveryDeadline: Task<Void, Never>?
    private var inviteDeadline: Task<Void, Never>?
    private var computerTurn: Task<Void, Never>?
    private var wantsDiscovery = false
    private var suspended = false
    private var didConnect = false
    private var leaving = false
    private var leaveDeadline: Task<Void, Never>?
    private var submission: Submission?
    private var submissionTimeout: Task<Void, Never>?
    private var overriddenSubmission: (window: ResponseWindow, feedback: DiscardClaimFeedback)?

    public private(set) var rooms: [DiscoveredRoom] = []
    public private(set) var update: RoomUpdate?
    public private(set) var connected = false
    public private(set) var needsHandReviewConfirmation = false
    public private(set) var revision = 0
    public private(set) var notice: String?
    public private(set) var openingRound: Int?
    public private(set) var recovery: Recovery?
    public private(set) var inviteSearch: InviteSearch?
    public var rackOrder: [Tile.ID]?

    public var table: TableState? {
        guard var table = update?.table else { return nil }
        if table.discardClaimFeedback == nil, let overriddenSubmission,
           overriddenSubmission.window.matchesSettledDiscard(in: table) {
            table.discardClaimFeedback = overriddenSubmission.feedback
        }
        return table
    }
    public var moveStatus: TableMoveStatus? {
        submission.map { $0.acknowledged ? .waitingForResolution : .sending }
    }
    public var players: [RoomPlayer] { update?.players ?? [] }
    public var paused: Bool { suspended || (host == nil && !connected) || update?.paused == true }
    public var canAdvance: Bool { host != nil }
    public var computerHasMove: Bool { !paused && host?.match.computerHasMove == true }
    public var managesComputerTurns: Bool { true }
    public var isBrowsing: Bool { browser != nil }
    public var isHost: Bool { host != nil }
    public var isInRoom: Bool { host != nil || target != nil }
    public var roomName: String? { host?.name ?? target?.name }
    public var roomID: UUID? { host?.id ?? target?.id }
    public var canStart: Bool { !suspended && host?.match.canStart == true }

    public func browse() {
        wantsDiscovery = true
        guard advertises, !suspended, browser == nil else { return }
        let search = NWBrowser(for: .bonjourWithTXTRecord(type: Self.service, domain: nil),
                               using: Self.parameters())
        browser = search
        search.stateUpdateHandler = { [weak self, weak search] state in
            Task { @MainActor [weak self] in
                guard let self, let search, browser === search else { return }
                switch state {
                case .ready:
                    if !isInRoom, inviteSearch == nil { notice = nil }
                case .waiting:
                    if !isInRoom { notice = "请确认 Wi-Fi 已开启，并在设置中允许本地网络访问。" }
                case .failed:
                    notice = "无法查找附近牌桌。请检查 Wi-Fi 和本地网络权限。"
                    closeBrowser()
                default: break
                }
            }
        }
        search.browseResultsChangedHandler = { [weak self, weak search] results, _ in
            Task { @MainActor [weak self] in
                guard let self, let search, browser === search else { return }
                readRooms(results)
            }
        }
        search.start(queue: .main)
    }

    public func stopBrowsing() {
        wantsDiscovery = false
        cancelInviteSearch()
        closeBrowser()
    }

    private func closeBrowser() {
        let current = browser
        browser = nil
        current?.cancel()
        rooms = []
    }

    public func create(name: String, ruleset: FuzhouRuleset = .pureSuit, houseRules: FuzhouHouseRules? = nil,
                       revealsSettledHands: Bool = false) {
        beginLobbyChoice()
        guard !isInRoom else { return }
        guard hostingAllowed() else { notice = "开启免费体验或解锁完整版后，可以创建牌桌。加入牌友的牌桌免费。"; return }
        cancelInviteSearch()
        let name = NearbyMatch.normalizedName(name)
        host = HostedRoom(name: name, match: NearbyMatch(hostName: name, ruleset: ruleset, houseRules: houseRules,
                                                       revealsSettledHands: revealsSettledHands))
        notice = nil
        broadcast()
        openListener()
    }

    public func join(_ room: DiscoveredRoom, name: String) {
        beginLobbyChoice()
        startJoin(room, name: { name })
    }

    private func startJoin(_ room: DiscoveredRoom, name: @MainActor () -> String) {
        guard !isInRoom, !needsSeatRead || readSeats() else { return }
        cancelInviteSearch()
        let previous = seat(in: room.id)
        guard previous == nil || previous?.hostKey == room.publicKey else {
            automaticallyReturning = false
            notice = "无法确认原来的房主，请向房主确认牌桌。"
            return
        }
        returningToSeat = previous != nil
        target = room
        guestName = previous?.guestName ?? NearbyMatch.normalizedName(name())
        seatKey = previous?.seatKey ?? UUID()
        didConnect = false
        notice = "正在加入牌桌…"
        connect(room)
    }

    public func confirmHandReview() {
        guard needsHandReviewConfirmation, let target,
              let index = seats.firstIndex(where: { $0.roomID == target.id }) else { return }
        seats[index].acceptsHandReview = true
        guard persistSeats() else { return }
        needsHandReviewConfirmation = false
        notice = "正在加入牌桌…"
        let room = rooms.first { $0.id == target.id && $0.publicKey == target.publicKey } ?? target
        connect(room)
    }

    public func declineHandReview() {
        guard needsHandReviewConfirmation, let target else { return }
        forgetSeat(in: target.id)
        resetRoom()
    }

    public func resumeLastRoom(automatically: Bool = false) {
        guard !isInRoom, !needsSeatRead || readSeats(), let last = seats.last else { return }
        if automatically && pendingInvite != nil { return }
        beginLobbyChoice()
        automaticallyReturning = automatically
        findRoom(PendingInvite(roomID: last.roomID, name: { last.guestName }))
    }

    /// An explicit lobby action takes priority until an automatic return is acknowledged.
    public func beginLobbyChoice() {
        if automaticallyReturning && target != nil { resetRoom() }
        automaticallyReturning = false
        cancelInviteSearch()
    }

    public func forgetLastRoom() {
        beginLobbyChoice()
        guard !isInRoom, let last = seats.last else { return }
        forgetSeat(in: last.roomID)
    }

    private func forgetSeat(in room: UUID) {
        guard seat(in: room) != nil else { return }
        seats.removeAll { $0.roomID == room }
        persistSeats()
    }

    public func retrySeatStorage() {
        if needsSeatRead { readSeats() }
        else if seatStorageIssue != nil { persistSeats() }
    }

    @discardableResult
    private func persistSeats() -> Bool {
        guard !needsSeatRead else { return false }
        guard let seatFile else { return true }
        do {
            if seats.isEmpty {
                do { try FileManager.default.removeItem(at: seatFile) }
                catch let error as CocoaError where error.code == .fileNoSuchFile {}
            } else {
                var directory = seatFile.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var attributes = URLResourceValues()
                attributes.isExcludedFromBackup = true
                try directory.setResourceValues(attributes)
                let data = try JSONEncoder().encode(SeatArchive(seats))
                #if os(iOS)
                try data.write(to: seatFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                #else
                try data.write(to: seatFile, options: .atomic)
                #endif
            }
            seatStorageIssue = nil
            return true
        } catch {
            seatStorageIssue = seats.last == nil ? "未能清除上次的座位记录。" : "未能保存座位记录。"
            return false
        }
    }

    public func joinInvite(_ id: UUID, name: String) {
        joinInvite(id, name: { name })
    }

    /// Reads the current nickname when a room is found and a new seat is needed.
    public func joinInvite(_ id: UUID, name: @escaping @MainActor () -> String) {
        beginLobbyChoice()
        findRoom(PendingInvite(roomID: id, name: name))
    }

    private func findRoom(_ invite: PendingInvite) {
        guard !isInRoom, !needsSeatRead || readSeats() else { return }
        pendingInvite = invite
        inviteSearch = .searching
        notice = "正在查找牌友邀请你加入的牌桌…"
        advanceInviteSearch()
        if pendingInvite != nil { browse() }
    }

    /// Keeps a discovered invitation pending while the player edits their nickname.
    public func setInviteJoiningDeferred(_ deferred: Bool) {
        guard inviteJoiningDeferred != deferred else { return }
        inviteJoiningDeferred = deferred
        if !deferred { advanceInviteSearch() }
    }

    public func retryInviteSearch() {
        guard let pendingInvite else { return }
        beginLobbyChoice()
        findRoom(pendingInvite)
    }

    public func cancelInviteSearch() {
        inviteDeadline?.cancel()
        inviteDeadline = nil
        pendingInvite = nil
        if inviteSearch != nil, !isInRoom { notice = nil }
        inviteSearch = nil
    }

    private func advanceInviteSearch() {
        guard let pendingInvite, inviteSearch == .searching, !suspended, !isInRoom else { return }
        guard let room = rooms.first(where: { $0.id == pendingInvite.roomID }) else {
            if inviteDeadline == nil { startInviteDeadline(for: pendingInvite.roomID) }
            return
        }
        if inviteJoiningDeferred {
            inviteDeadline?.cancel()
            inviteDeadline = nil
            return
        }
        startJoin(room, name: pendingInvite.name)
    }

    private func startInviteDeadline(for roomID: UUID) {
        let delay = inviteTimeout
        inviteDeadline = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, pendingInvite?.roomID == roomID, inviteSearch == .searching, !suspended else { return }
            inviteDeadline = nil
            inviteSearch = .unavailable
            notice = "没找到这张牌桌。请打开 Wi-Fi，并确认房主在附近，牌桌还没关闭。"
        }
    }

    public func startMatch() {
        var random = SystemRandomNumberGenerator()
        startMatch(using: &random)
    }

    func startMatch(using random: inout some RandomNumberGenerator) {
        guard hostingAllowed() else { notice = "当前无法开局。解锁完整版后可以继续做房主。"; return }
        guard listener != nil, host?.match.start(using: &random) == true else { return }
        broadcast()
    }

    public func submit(_ move: Move) -> Bool {
        guard !paused, submission == nil, let update, update.table?.canSubmit(move) == true else { return false }
        var submitted = Submission(move: move, revision: update.revision, window: ResponseWindow(update.table))
        if host != nil {
            guard host?.match.submit(move, seat: .east, basedOn: update.revision) == true else { return false }
            if submitted.window != nil {
                submitted.acknowledged = true
                submission = submitted
            }
            broadcast()
            return true
        }
        guard let wireID = guest?.wire.id, sendToHost(.move(move, update.revision, id: submitted.id)) else { return false }
        submission = submitted
        let id = submitted.id
        submissionTimeout = Task { [weak self, moveReplyTimeout] in
            do { try await Task.sleep(for: moveReplyTimeout) } catch { return }
            guard let self, submission?.id == id, submission?.acknowledged == false,
                  connected, let wire = guest?.wire, wire.id == wireID else { return }
            // Rejoining replaces the old link on the host before it sends a fresh table.
            // Keep the submission so that snapshot can tell us whether the host recorded it.
            wire.close()
        }
        return true
    }

    private func clearSubmission() {
        submissionTimeout?.cancel()
        submissionTimeout = nil
        submission = nil
    }

    private func reconcileSubmission(with update: RoomUpdate) {
        if let previous = overriddenSubmission,
           update.table.map({ previous.window.matchesSettledDiscard(in: $0) }) != true {
            overriddenSubmission = nil
        }
        guard var submission else { return }
        let receipt = update.moveReceipt.flatMap { $0.id == submission.id ? $0 : nil }
        if let window = submission.window, ResponseWindow(update.table) != window {
            // A higher-priority claim can settle before this guest's move reaches the host.
            if let table = update.table, table.discardClaimFeedback == nil, submission.move != .pass,
               let winner = window.overridingMove(in: table) {
                overriddenSubmission = (window, .overridden(submission.move, by: winner))
            }
            clearSubmission()
            return
        }
        if receipt?.accepted == false { clearSubmission(); return }
        if submission.window != nil {
            // Older hosts omit receipts. Their projection removes your move once it is recorded.
            let recorded = update.revision > submission.revision && update.table?.canSubmit(submission.move) == false
            if !submission.acknowledged, receipt?.accepted == true || recorded {
                submission.acknowledged = true
                self.submission = submission
                submissionTimeout?.cancel()
                submissionTimeout = nil
            }
        } else if receipt != nil || (update.revision > submission.revision && update.table?.canSubmit(submission.move) != true) {
            clearSubmission()
        }
    }

    public func advanceComputer() {
        if !paused, host?.match.advanceComputer() == true { broadcast() }
    }

    public func finishOpening(_ round: Int) {
        guard openingRound == round else { return }
        openingRound = nil
        scheduleComputerTurn()
    }

    public func nextHand() {
        if host != nil, hostingAllowed(), !paused, host?.match.nextHand() == true { broadcast() }
    }

    public func substitute(_ seat: Seat) {
        guard host?.match.players.contains(where: { $0.seat == seat && !$0.connected }) == true,
              host?.match.release(seat) == true else { return }
        broadcast()
    }

    public func setBackgrounded(_ inBackground: Bool) {
        guard suspended != inBackground else { return }
        suspended = inBackground
        revision += 1
        computerTurn?.cancel()
        computerTurn = nil
        if suspended {
            openingRound = nil
            closeBrowser()
            inviteDeadline?.cancel()
            inviteDeadline = nil
            stopListener()
            retry?.cancel()
            retry = nil
            recoveryDeadline?.cancel()
            recoveryDeadline = nil
            let connections = links.values.map(\.wire)
            connections.forEach { $0.close() }
            guest?.wire.close()
        } else if host != nil {
            openListener()
        } else if target != nil {
            browse()
            if didConnect { beginRecovery() }
            else { tryReconnect() }
        }
        if !suspended, wantsDiscovery { browse() }
        if !suspended {
            advanceInviteSearch()
            scheduleComputerTurn()
        }
    }

    public func retryRecovery() {
        guard recovery == .unavailable, !suspended else { return }
        recovery = nil
        beginRecovery()
    }

    public func returnToLobby() {
        guard host == nil, target != nil, !connected else { return }
        resetRoom()
    }

    public func leave() {
        guard !leaving else { return }
        if host != nil {
            let closing = Array(links.values)
            for link in closing where link.seat != nil { sendToGuest(.closed, wire: link.wire) }
            links = [:]
            resetRoom()
            closing.forEach { $0.wire.finishSending() }
            return
        }
        // An explicit exit releases the guest seat. A transport loss keeps it reserved.
        if connected, let wire = guest?.wire, sendToHost(.leave) {
            leaving = true
            // Keep receiving until the host confirms that it released this seat.
            leaveDeadline = Task { [weak wire] in
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                wire?.close()
            }
            return
        }
        let hadGuestSeat = target != nil
        resetRoom()
        if hadGuestSeat { notice = "未收到房主的离桌确认。可返回上次牌桌查看座位。" }
    }

    private func resetRoom() {
        host = nil
        target = nil
        update = nil
        needsHandReviewConfirmation = false
        clearSubmission()
        overriddenSubmission = nil
        openingRound = nil
        rackOrder = nil
        cancelInviteSearch()
        computerTurn?.cancel()
        computerTurn = nil
        connected = false
        leaving = false
        leaveDeadline?.cancel()
        leaveDeadline = nil
        didConnect = false
        returningToSeat = false
        automaticallyReturning = false
        retry?.cancel()
        retry = nil
        clearRecovery()
        stopListener()
        let connections = links.values.map(\.wire)
        links = [:]
        connections.forEach { $0.close() }
        let departing = guest
        guest = nil
        departing?.wire.close()
        notice = nil
        revision += 1
    }

    private static func parameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        tcp.keepaliveInterval = 3
        tcp.keepaliveCount = 3
        tcp.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }

    private func readRooms(_ results: Set<NWBrowser.Result>) {
        var available: [UUID: DiscoveredRoom] = [:]
        for result in results {
            guard case .bonjour(let txt) = result.metadata,
                  txt["v"] == "1", let rawID = txt["id"], let id = UUID(uuidString: rawID),
                  let name = txt["name"], let rawKey = txt["key"], let key = Data(base64Encoded: rawKey),
                  key.count == 32, id != host?.id else { continue }
            available[id] = DiscoveredRoom(id: id, name: NearbyMatch.normalizedName(name),
                                            endpoint: result.endpoint, publicKey: key)
        }
        discoveredRoomsChanged(available)
    }

    func discoveredRoomsChanged(_ available: [UUID: DiscoveredRoom]) {
        rooms = available.values.sorted { ($0.name, $0.code) < ($1.name, $1.code) }
        advanceInviteSearch()
        if let target, let discovered = available[target.id], discovered.publicKey == target.publicKey, guest == nil {
            tryReconnect()
        }
    }

    static func roomTXTRecord(id: UUID, name: String, publicKey: Data) -> NWTXTRecord {
        // A single TXT entry must fit its key, separator, and value in 255 bytes.
        var remainingBytes = 240
        var label = ""
        for character in name {
            let bytes = String(character).utf8.count
            guard bytes <= remainingBytes else { break }
            label.append(character)
            remainingBytes -= bytes
        }
        return NWTXTRecord(["v": "1", "id": id.uuidString, "name": NearbyMatch.normalizedName(label),
                            "key": publicKey.base64EncodedString()])
    }

    private func openListener() {
        guard let host, !suspended, listener == nil else { return }
        do {
            let parameters = Self.parameters()
            if !advertises {
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            }
            let open = try NWListener(using: parameters)
            if advertises {
                let txt = Self.roomTXTRecord(id: host.id, name: host.name,
                                             publicKey: host.agreementKey.publicKey.rawRepresentation)
                open.service = NWListener.Service(name: host.id.uuidString, type: Self.service, txtRecord: txt)
            }
            listener = open
            open.newConnectionHandler = { [weak self, weak open] connection in
                Task { @MainActor [weak self] in
                    guard let self, let open, listener === open else { connection.cancel(); return }
                    accept(connection)
                }
            }
            open.stateUpdateHandler = { [weak self, weak open] state in
                Task { @MainActor [weak self] in
                    guard let self, let open, listener === open else { return }
                    switch state {
                    case .ready: notice = nil
                    case .waiting:
                        notice = "请确认 Wi-Fi 已开启，并允许本地网络访问。"
                    case .failed:
                        notice = "无法创建牌桌。请在设置中检查本地网络访问权限。"
                        stopListener()
                    default: break
                    }
                }
            }
            open.start(queue: .main)
        } catch {
            notice = "无法创建牌桌。请在设置中检查本地网络访问权限。"
        }
    }

    private func stopListener() {
        let open = listener
        listener = nil
        open?.cancel()
    }

    private func accept(_ connection: NWConnection) {
        guard links.count < 8 else { connection.cancel(); return }
        let wire = NearbyWire(connection)
        links[wire.id] = Link(wire: wire)
        wire.received = { [weak self] wire, data in self?.hostReceived(data, from: wire) }
        wire.ended = { [weak self] wire in self?.hostLost(wire) }
        wire.start()
    }

    private func hostReceived(_ data: Data, from wire: NearbyWire) {
        guard let host, var link = links[wire.id] else { wire.close(); return }
        do {
            if link.cipher == nil {
                link.cipher = try NearbyCipher(own: host.agreementKey, peer: data, room: host.id, host: true)
                links[wire.id] = link
                return
            }
            guard let clear = try link.cipher?.open(data) else { wire.close(); return }
            links[wire.id] = link
            switch try JSONDecoder().decode(GuestMessage.self, from: clear) {
            case let .join(key, name, supportsHandReview, acceptsHandReview):
                guard link.seat == nil else { wire.close(); return }
                if host.match.revealsSettledHands, supportsHandReview == true, acceptsHandReview != true {
                    sendToGuest(.handReviewConfirmationRequired, wire: wire)
                    return
                }
                guard let seat = self.host?.match.join(key: key, name: name,
                                                       acceptsHandReview: supportsHandReview == true && acceptsHandReview == true) else {
                    sendToGuest(.rejected, wire: wire)
                    return
                }
                for previous in Array(links.values) where previous.seat == seat && previous.wire.id != wire.id {
                    links.removeValue(forKey: previous.wire.id)
                    previous.wire.close()
                }
                links[wire.id]?.seat = seat
                wire.accepted()
                broadcast()
            case let .move(move, basedOn, id):
                guard let seat = link.seat else { wire.close(); return }
                if self.host?.match.submit(move, seat: seat, basedOn: basedOn) == true {
                    broadcast(receipt: id.map { RoomUpdate.MoveReceipt(id: $0, accepted: true) }, to: seat)
                } else if var update = self.host?.match.update(for: seat) {
                    update.moveReceipt = id.map { RoomUpdate.MoveReceipt(id: $0, accepted: false) }
                    sendToGuest(.update(update), wire: wire)
                }
            case .leave:
                guard let seat = link.seat else { wire.close(); return }
                _ = self.host?.match.release(seat)
                links[wire.id]?.seat = nil
                sendToGuest(.closed, wire: wire)
                broadcast()
            }
        } catch {
            wire.close()
        }
    }

    private func hostLost(_ wire: NearbyWire) {
        if let link = links.removeValue(forKey: wire.id), let seat = link.seat {
            host?.match.disconnect(seat)
            broadcast()
        }
    }

    private func broadcast(receipt: RoomUpdate.MoveReceipt? = nil, to recipient: Seat? = nil) {
        guard let host else { return }
        publish(host.match.update(for: .east))
        for link in Array(links.values) {
            if let seat = link.seat {
                var update = host.match.update(for: seat)
                if seat == recipient { update.moveReceipt = receipt }
                sendToGuest(.update(update), wire: link.wire)
            }
        }
        scheduleComputerTurn()
    }

    private func scheduleComputerTurn() {
        computerTurn?.cancel()
        computerTurn = nil
        guard computerHasMove, openingRound == nil, let roomID = host?.id else { return }
        let expectedRevision = update?.revision
        let delay = table?.step == .turn ? Int.random(in: 1150...1420) : Int.random(in: 220...360)
        computerTurn = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(delay)) } catch { return }
            guard let self, !Task.isCancelled, host?.id == roomID,
                  update?.revision == expectedRevision, openingRound == nil, computerHasMove else { return }
            computerTurn = nil
            advanceComputer()
        }
    }

    private func sendToGuest(_ message: HostMessage, wire: NearbyWire) {
        guard var link = links[wire.id] else { return }
        do {
            guard let data = try link.cipher?.seal(JSONEncoder().encode(message)) else { wire.close(); return }
            links[wire.id] = link
            wire.send(data)
        } catch { wire.close() }
    }

    private func prepareSeatForJoin(_ room: DiscoveredRoom) -> Bool {
        if seat(in: room.id) != nil {
            return seatStorageIssue == nil || persistSeats()
        }
        // The host may reserve this key even if its first reply never arrives.
        seats.append(GuestSeat(roomID: room.id, hostKey: room.publicKey, hostName: room.name,
                               seatKey: seatKey, guestName: guestName))
        return persistSeats()
    }

    private func connect(_ room: DiscoveredRoom) {
        guard guest == nil, !suspended else { return }
        let own = Curve25519.KeyAgreement.PrivateKey()
        do {
            let cipher = try NearbyCipher(own: own, peer: room.publicKey, room: room.id, host: false)
            let wire = NearbyWire(NWConnection(to: room.endpoint, using: Self.parameters()))
            guest = Link(wire: wire, cipher: cipher)
            let guestKey = own.publicKey.rawRepresentation
            wire.opened = { [weak self] wire in
                guard let self, guest?.wire.id == wire.id else { return }
                guard prepareSeatForJoin(room) else { resetRoom(); return }
                wire.send(guestKey)
                _ = sendToHost(.join(seatKey, guestName, supportsHandReview: true,
                                     acceptsHandReview: seat(in: room.id)?.acceptsHandReview))
            }
            wire.received = { [weak self] wire, frame in self?.guestReceived(frame, from: wire) }
            wire.ended = { [weak self] wire in self?.guestLost(wire) }
            wire.start()
        } catch {
            automaticallyReturning = false
            notice = "连不上这张牌桌。请在列表中重新选择。"
            target = nil
        }
    }

    private func guestReceived(_ data: Data, from wire: NearbyWire) {
        guard var link = guest, link.wire.id == wire.id, let target else { return }
        do {
            guard let clear = try link.cipher?.open(data) else { wire.close(); return }
            guest = link
            switch try JSONDecoder().decode(HostMessage.self, from: clear) {
            case .update(let update):
                guard !leaving else { return }
                let resuming = !connected && (didConnect || returningToSeat)
                connected = true
                didConnect = true
                clearRecovery()
                notice = nil
                automaticallyReturning = false
                if var accepted = seat(in: target.id), accepted.confirmed != true || seats.last != accepted {
                    accepted.confirmed = true
                    seats.removeAll { $0.roomID == target.id }
                    seats.append(accepted)
                    persistSeats()
                }
                wire.accepted()
                publish(update, resuming: resuming)
            case .handReviewConfirmationRequired:
                // A guest awaiting consent has no host reservation and can decide while disconnected.
                guest = nil
                wire.close()
                clearRecovery()
                automaticallyReturning = false
                needsHandReviewConfirmation = true
                notice = nil
            case .rejected:
                let returning = didConnect || seat(in: target.id)?.confirmed == true
                forgetSeat(in: target.id)
                resetRoom()
                notice = returning ? "原来的座位已释放。请让房主新建牌桌后再邀请你。" : "牌桌已满或对局已开始。"
            case .closed:
                let hostEndedRoom = !leaving
                forgetSeat(in: target.id)
                resetRoom()
                if hostEndedRoom { notice = "房主已结束牌桌。" }
            }
        } catch { wire.close() }
    }

    private func guestLost(_ wire: NearbyWire) {
        guard guest?.wire.id == wire.id else { return }
        guest = nil
        connected = false
        openingRound = nil
        revision += 1
        if leaving {
            resetRoom()
            notice = "未收到房主的离桌确认。可返回上次牌桌查看座位。"
        } else if !didConnect, !suspended {
            automaticallyReturning = false
            target = nil
            notice = "没能加入牌桌。请检查 Wi-Fi，再试一次。"
        } else if target != nil {
            beginRecovery()
        }
    }

    private func beginRecovery() {
        guard !suspended, !connected, !leaving, recovery != .unavailable, let roomID = target?.id else { return }
        recovery = .reconnecting
        if recoveryDeadline == nil {
            recoveryDeadline = Task { [weak self] in
                guard let delay = self?.recoveryTimeout else { return }
                do { try await Task.sleep(for: delay) } catch { return }
                guard let self, target?.id == roomID, !connected, !suspended else { return }
                recoveryDeadline = nil
                recovery = .unavailable
                retry?.cancel()
                retry = nil
                guest?.wire.close()
            }
        }
        tryReconnect()
    }

    private func clearRecovery() {
        recoveryDeadline?.cancel()
        recoveryDeadline = nil
        recovery = nil
    }

    private func tryReconnect() {
        guard !suspended, !needsHandReviewConfirmation, recovery != .unavailable,
              guest == nil, retry == nil, let target else { return }
        retry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard let self else { return }
            retry = nil
            guard self.target?.id == target.id else { return }
            let fresh = rooms.first { $0.id == target.id && $0.publicKey == target.publicKey }
            connect(fresh ?? target)
        }
    }

    private func sendToHost(_ message: GuestMessage) -> Bool {
        guard var link = guest else { return false }
        do {
            guard let data = try link.cipher?.seal(JSONEncoder().encode(message)) else { return false }
            guest = link
            link.wire.send(data)
            return true
        } catch {
            link.wire.close()
            return false
        }
    }

    private func publish(_ update: RoomUpdate, resuming: Bool = false) {
        reconcileSubmission(with: update)
        // Any unrecorded request from the replaced link can no longer reach the host.
        if resuming, submission?.acknowledged == false { clearSubmission() }
        let previous = self.update?.table
        let startsHand = previous?.roundNumber != update.table?.roundNumber ||
            (previous?.result != nil && update.table?.result == nil)
        if startsHand { rackOrder = nil }
        if let table = update.table, table.isOpeningLayout, startsHand {
            // Guests animate the initial deal. Subsequent deals and reconnects present the host's board immediately.
            openingRound = !resuming && (isHost || previous == nil) ? table.roundNumber : nil
        } else if resuming || update.table?.isOpeningLayout != true ||
                    previous?.step != update.table?.step || previous?.lastDraw != update.table?.lastDraw {
            openingRound = nil
        }
        self.update = update
        revision += 1
    }
}
