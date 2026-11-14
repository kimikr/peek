import CommonCrypto
import CryptoKit
import Foundation

/// The shared secret from the pairing link. It never travels over the network:
/// requests are authenticated with an HMAC, and every body that matters (the certificate
/// upload, screenshots, and all of the server's replies) is encrypted and authenticated.
struct PairingKey: Equatable {
    let token: Data

    struct Unreadable: LocalizedError {
        var errorDescription: String? { "A reply from the dev server could not be decrypted (is it paired with another phone?)." }
    }

    init?(hex: String) {
        guard hex.count == 32 else { return nil }
        var bytes = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        token = bytes
    }

    private func derive(_ label: String) -> SymmetricKey {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(label.utf8), using: SymmetricKey(data: token))
        return SymmetricKey(data: Data(mac))
    }

    private static func hex<D: Sequence>(_ bytes: D) -> String where D.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Public identifier the dev server advertises over Bonjour, so the phone finds its own server.
    var serverID: String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data("peek-id".utf8), using: SymmetricKey(data: token))
        return Self.hex(mac.prefix(4))
    }

    /// `X-Peek-Auth` value: `<unix time>:<hex HMAC>` over the request line, the time, the body's
    /// SHA-256 and the headers the server acts on (the bundle identifier it signs builds under).
    func authHeader(method: String, path: String, body: Data, bundle: String, device: String) -> String {
        let stamp = Int(Date().timeIntervalSince1970)
        let message = "\(method)\n\(path)\n\(stamp)\n\(Self.hex(SHA256.hash(data: body)))\n\(bundle)\n\(device)"
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: derive("peek-auth"))
        return "\(stamp):" + Self.hex(mac)
    }

    /// nonce(16) | AES-256-CTR(plaintext) | HMAC-SHA256(nonce | ciphertext): encrypt-then-MAC,
    /// matching the dev server, which uses the openssl command for AES.
    func seal(_ plaintext: Data) -> Data {
        var nonce = Data(count: 16)
        nonce.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let body = Self.ctr(plaintext, key: derive("peek-enc"), nonce: nonce)
        let tag = HMAC<SHA256>.authenticationCode(for: nonce + body, using: derive("peek-mac"))
        return nonce + body + Data(tag)
    }

    func open(_ sealed: Data) throws -> Data {
        guard sealed.count >= 48 else { throw Unreadable() }
        let nonce = sealed.prefix(16)
        let body = sealed.dropFirst(16).dropLast(32)
        let tag = sealed.suffix(32)
        guard HMAC<SHA256>.isValidAuthenticationCode(tag, authenticating: Data(nonce + body), using: derive("peek-mac")) else {
            throw Unreadable()
        }
        return Self.ctr(Data(body), key: derive("peek-enc"), nonce: Data(nonce))
    }

    /// AES-256 in counter mode with the nonce as the initial 128-bit big-endian counter block.
    private static func ctr(_ input: Data, key: SymmetricKey, nonce: Data) -> Data {
        guard !input.isEmpty else { return Data() }
        var output = Data(count: input.count)
        key.withUnsafeBytes { keyBytes in
            nonce.withUnsafeBytes { iv in
                var cryptor: CCCryptorRef?
                CCCryptorCreateWithMode(CCOperation(kCCEncrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES),
                                        CCPadding(ccNoPadding), iv.baseAddress, keyBytes.baseAddress, keyBytes.count,
                                        nil, 0, 0, CCModeOptions(kCCModeOptionCTR_BE), &cryptor)
                guard let cryptor else { return }
                defer { CCCryptorRelease(cryptor) }
                let count = output.count
                input.withUnsafeBytes { inBytes in
                    output.withUnsafeMutableBytes { outBytes in
                        var moved = 0
                        _ = CCCryptorUpdate(cryptor, inBytes.baseAddress, input.count, outBytes.baseAddress, count, &moved)
                    }
                }
            }
        }
        return output
    }
}
