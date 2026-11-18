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

    @ObservationIgnored private let hostingAllowed: @MainActor () -> Bool

    public init(hostingAllowed: @escaping @MainActor () -> Bool) {
        self.hostingAllowed = hostingAllowed
        advertises = true
        recoveryTimeout = .seconds(15)
        inviteTimeout = .seconds(15)
    }

    init(loopback: Bool, recoveryTimeout: Duration = .seconds(15), inviteTimeout: Duration = .seconds(15),
         hostingAllowed: @escaping @MainActor () -> Bool = { true }) {
        self.hostingAllowed = hostingAllowed
        advertises = !loopback
        self.recoveryTimeout = recoveryTimeout
        self.inviteTimeout = inviteTimeout
    }

    var loopbackRoom: DiscoveredRoom? {
        guard !advertises, let host, let port = listener?.port, port != .any else { return nil }
        return DiscoveredRoom(id: host.id, name: host.name, endpoint: .hostPort(host: "127.0.0.1", port: port),
                              publicKey: host.agreementKey.publicKey.rawRepresentation)
    }

    private enum GuestMessage: Codable {
        case join(UUID, String)
        case move(Move, Int)
        case leave
    }

    private enum HostMessage: Codable {
        case update(RoomUpdate)
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

    private var browser: NWBrowser?
    private var listener: NWListener?
    private var host: HostedRoom?
    private var links: [UUID: Link] = [:]
    private var guest: Link?
    private var target: DiscoveredRoom?
    private var seatKey = UUID()
    private var guestName = ""
    private var pendingInvite: UUID?
    private var retry: Task<Void, Never>?
    private var recoveryDeadline: Task<Void, Never>?
    private var inviteDeadline: Task<Void, Never>?
    private var computerTurn: Task<Void, Never>?
    private var wantsDiscovery = false
    private var suspended = false
    private var didConnect = false
    private var leaving = false

    public private(set) var rooms: [DiscoveredRoom] = []
    public private(set) var update: RoomUpdate?
    public private(set) var connected = false
    public private(set) var revision = 0
    public private(set) var notice: String?
    public private(set) var openingRound: Int?
    public private(set) var recovery: Recovery?
    public private(set) var inviteSearch: InviteSearch?
    public var rackOrder: [Tile.ID]?

    public var table: TableState? { update?.table }
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

    public func create(name: String) {
        guard !isInRoom else { return }
        guard hostingAllowed() else { notice = "创建牌桌需要有效的体验或完整版权限，加入牌友的牌桌始终免费。"; return }
        cancelInviteSearch()
        let name = NearbyMatch.normalizedName(name)
        host = HostedRoom(name: name, match: NearbyMatch(hostName: name))
        notice = nil
        broadcast()
        openListener()
    }

    public func join(_ room: DiscoveredRoom, name: String) {
        guard !isInRoom else { return }
        cancelInviteSearch()
        target = room
        guestName = NearbyMatch.normalizedName(name)
        seatKey = UUID()
        didConnect = false
        notice = "正在加入牌桌…"
        connect(room)
    }

    public func joinInvite(_ id: UUID, name: String) {
        guard !isInRoom else { return }
        guestName = NearbyMatch.normalizedName(name)
        if let room = rooms.first(where: { $0.id == id }) {
            join(room, name: guestName)
        } else {
            pendingInvite = id
            inviteSearch = .searching
            notice = "正在查找邀请中的牌桌…"
            browse()
            startInviteDeadline()
        }
    }

    public func retryInviteSearch() {
        guard let pendingInvite else { return }
        joinInvite(pendingInvite, name: guestName)
    }

    public func cancelInviteSearch() {
        inviteDeadline?.cancel()
        inviteDeadline = nil
        pendingInvite = nil
        if inviteSearch != nil, !isInRoom { notice = nil }
        inviteSearch = nil
    }

    private func startInviteDeadline() {
        inviteDeadline?.cancel()
        guard let pendingInvite, inviteSearch == .searching, !suspended else { return }
        let delay = inviteTimeout
        inviteDeadline = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, self.pendingInvite == pendingInvite, inviteSearch == .searching, !suspended else { return }
            inviteDeadline = nil
            inviteSearch = .unavailable
            notice = "未找到邀请中的牌桌。请确认房主仍在附近、牌桌仍开放，并已开启 Wi-Fi。"
        }
    }

    public func startMatch() {
        guard hostingAllowed() else { notice = "体验已结束，解锁完整版后可以继续做房主。"; return }
        guard listener != nil, host?.match.start() == true else { return }
        broadcast()
    }

    public func submit(_ move: Move) -> Bool {
        guard !paused, let update, table?.moves.contains(move) == true else { return false }
        if host != nil {
            guard host?.match.submit(move, seat: .east, basedOn: update.revision) == true else { return false }
            broadcast()
            return true
        }
        return sendToHost(.move(move, update.revision))
    }

    public func advanceComputer() {
        if !paused, host?.match.advanceComputer() == true { broadcast() }
    }

    public func finishOpening(_ round: Int) {
        if openingRound == round { openingRound = nil }
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
            startInviteDeadline()
            scheduleComputerTurn()
        }
    }

    public func retryRecovery() {
        guard recovery == .unavailable, !suspended else { return }
        recovery = nil
        beginRecovery()
    }

    public func leave() {
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
            wire.finishSending()
            return
        }
        resetRoom()
    }

    private func resetRoom() {
        host = nil
        target = nil
        update = nil
        openingRound = nil
        rackOrder = nil
        cancelInviteSearch()
        computerTurn?.cancel()
        computerTurn = nil
        connected = false
        leaving = false
        didConnect = false
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
        rooms = available.values.sorted { ($0.name, $0.code) < ($1.name, $1.code) }
        if let pendingInvite, inviteSearch == .searching, let room = available[pendingInvite], !isInRoom {
            join(room, name: guestName)
        } else if let target, let discovered = available[target.id],
                  discovered.publicKey == target.publicKey, guest == nil {
            tryReconnect()
        }
    }

    private func openListener() {
        guard let host, !suspended, listener == nil else { return }
        do {
            let parameters = Self.parameters()
            if !advertises {
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            }
            let open = try NWListener(using: parameters)
            let txt = NWTXTRecord(["v": "1", "id": host.id.uuidString, "name": host.name,
                                   "key": host.agreementKey.publicKey.rawRepresentation.base64EncodedString()])
            if advertises {
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
                        notice = "无法开启牌桌，请检查本地网络权限。"
                        stopListener()
                    default: break
                    }
                }
            }
            open.start(queue: .main)
        } catch {
            notice = "无法开启牌桌，请检查本地网络权限。"
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
            case let .join(key, name):
                guard link.seat == nil else { wire.close(); return }
                guard let seat = self.host?.match.join(key: key, name: name) else {
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
            case let .move(move, basedOn):
                guard let seat = link.seat else { wire.close(); return }
                if self.host?.match.submit(move, seat: seat, basedOn: basedOn) == true {
                    broadcast()
                } else if let update = self.host?.match.update(for: seat) {
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

    private func broadcast() {
        guard let host else { return }
        publish(host.match.update(for: .east))
        for link in Array(links.values) {
            if let seat = link.seat {
                sendToGuest(.update(host.match.update(for: seat)), wire: link.wire)
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
                wire.send(guestKey)
                _ = sendToHost(.join(seatKey, guestName))
            }
            wire.received = { [weak self] wire, frame in self?.guestReceived(frame, from: wire) }
            wire.ended = { [weak self] wire in self?.guestLost(wire) }
            wire.start()
        } catch {
            notice = "无法连接牌桌。请重新选择。"
            target = nil
        }
    }

    private func guestReceived(_ data: Data, from wire: NearbyWire) {
        guard var link = guest, link.wire.id == wire.id else { return }
        do {
            guard let clear = try link.cipher?.open(data) else { wire.close(); return }
            guest = link
            switch try JSONDecoder().decode(HostMessage.self, from: clear) {
            case .update(let update):
                connected = true
                didConnect = true
                clearRecovery()
                notice = nil
                wire.accepted()
                publish(update)
            case .rejected:
                resetRoom()
                notice = "牌桌已满或对局已开始。"
            case .closed:
                let hostEndedRoom = !leaving
                resetRoom()
                if hostEndedRoom { notice = "房主已结束牌桌。" }
            }
        } catch { wire.close() }
    }

    private func guestLost(_ wire: NearbyWire) {
        guard guest?.wire.id == wire.id else { return }
        guest = nil
        connected = false
        revision += 1
        if leaving {
            resetRoom()
        } else if !didConnect, !suspended {
            target = nil
            notice = "未能加入。请检查 Wi-Fi 后重试。"
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
        guard !suspended, recovery != .unavailable, guest == nil, retry == nil, let target else { return }
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

    private func publish(_ update: RoomUpdate) {
        if self.update?.table?.roundNumber != update.table?.roundNumber ||
            (self.update?.table?.result != nil && update.table?.result == nil) { rackOrder = nil }
        if let table = update.table, table.isOpeningLayout,
           self.update?.table?.roundNumber != table.roundNumber || self.update?.table?.result != nil {
            openingRound = table.roundNumber
        } else if update.table?.isOpeningLayout != true {
            openingRound = nil
        }
        self.update = update
        revision += 1
    }
}
