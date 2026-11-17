import CryptoKit
import Foundation

/// Each guest makes a fresh key for each connection. The host's key comes from its Bonjour service.
public struct NearbyCipher {
    private let sendingKey: SymmetricKey
    private let receivingKey: SymmetricKey
    private var sent: UInt64 = 0
    private var received: UInt64 = 0

    public init(own: Curve25519.KeyAgreement.PrivateKey, peer: Data, room: UUID, host: Bool) throws {
        let key = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peer)
        let shared = try own.sharedSecretFromKeyAgreement(with: key)
        let salt = Data(room.uuidString.utf8)
        let toHost = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: salt, sharedInfo: Data("fuzhou-v1-guest".utf8), outputByteCount: 32
        )
        let toGuest = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: salt, sharedInfo: Data("fuzhou-v1-host".utf8), outputByteCount: 32
        )
        sendingKey = host ? toGuest : toHost
        receivingKey = host ? toHost : toGuest
    }

    public mutating func seal(_ clear: Data) throws -> Data {
        let frame = try ChaChaPoly.seal(clear, using: sendingKey, authenticating: Self.bytes(sent))
        sent += 1
        return frame.combined
    }

    public mutating func open(_ frame: Data) throws -> Data {
        let clear = try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: frame), using: receivingKey,
                                        authenticating: Self.bytes(received))
        received += 1
        return clear
    }

    private static func bytes(_ counter: UInt64) -> Data {
        withUnsafeBytes(of: counter.bigEndian) { Data($0) }
    }
}
