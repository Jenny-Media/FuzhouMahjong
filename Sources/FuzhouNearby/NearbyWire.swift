import Foundation
import Network

@MainActor
final class NearbyWire {
    private static let limit = 64 * 1024
    let id = UUID()
    private let connection: NWConnection
    private var closed = false
    private var timeout: Task<Void, Never>?
    var opened: ((NearbyWire) -> Void)?
    var received: ((NearbyWire, Data) -> Void)?
    var ended: ((NearbyWire) -> Void)?

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    func start() {
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            self?.close()
        }
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.change(state) }
        }
        connection.start(queue: .main)
    }

    func accepted() {
        timeout?.cancel()
        timeout = nil
    }

    private func change(_ state: NWConnection.State) {
        guard !closed else { return }
        switch state {
        case .ready:
            receiveHeader()
            opened?(self)
        case .failed, .cancelled:
            close()
        default: break
        }
    }

    func send(_ body: Data) {
        guard !closed, !body.isEmpty, body.count <= Self.limit else { close(); return }
        var length = UInt32(body.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(body)
        connection.send(content: frame, completion: .contentProcessed { [weak self] error in
            if error != nil { Task { @MainActor in self?.close() } }
        })
    }

    private func receiveHeader() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            Task { @MainActor [weak self] in
                guard let self, !closed else { return }
                guard let data, data.count == 4, error == nil else { close(); return }
                let count = data.reduce(0) { $0 << 8 | Int($1) }
                guard (1...Self.limit).contains(count) else { close(); return }
                receiveBody(length: count)
            }
        }
    }

    private func receiveBody(length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, _, error in
            Task { @MainActor [weak self] in
                guard let self, !closed else { return }
                guard let data, data.count == length, error == nil else { close(); return }
                received?(self, data)
                if !closed { receiveHeader() }
            }
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        timeout?.cancel()
        connection.stateUpdateHandler = nil
        connection.cancel()
        ended?(self)
    }

    func finishSending() {
        guard !closed else { return }
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { _ in })
        Task { [self] in
            try? await Task.sleep(for: .seconds(2))
            close()
        }
    }
}
