import CryptoKit
import Foundation

enum KeePassTOTP {
    enum Failure: LocalizedError {
        case invalid
        var errorDescription: String? { "This entry has an invalid or unsupported one-time code configuration." }
    }

    static func generate(_ uri: String, at date: Date) throws -> String {
        guard let components = URLComponents(string: uri), components.scheme == "otpauth",
            components.host == "totp"
        else { throw Failure.invalid }
        var parameters: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard parameters[item.name] == nil, let value = item.value else { throw Failure.invalid }
            parameters[item.name] = value
        }
        guard let secret = parameters["secret"], let bytes = decodeBase32(secret), !bytes.isEmpty,
            let digits = Int(parameters["digits"] ?? "6"), (6...8).contains(digits),
            let period = UInt64(parameters["period"] ?? "30"), period > 0,
            date.timeIntervalSince1970.isFinite, date.timeIntervalSince1970 >= 0,
            date.timeIntervalSince1970 < Double(UInt64.max)
        else { throw Failure.invalid }
        var counter = (UInt64(date.timeIntervalSince1970) / period).bigEndian
        let data = withUnsafeBytes(of: &counter) { Data($0) }
        let key = SymmetricKey(data: bytes)
        let hash: [UInt8]
        switch (parameters["algorithm"] ?? "SHA1").uppercased().replacingOccurrences(of: "-", with: "") {
        case "SHA1": hash = Array(HMAC<Insecure.SHA1>.authenticationCode(for: data, using: key))
        case "SHA256": hash = Array(HMAC<SHA256>.authenticationCode(for: data, using: key))
        case "SHA512": hash = Array(HMAC<SHA512>.authenticationCode(for: data, using: key))
        default: throw Failure.invalid
        }
        let offset = Int(hash[hash.count - 1] & 15)
        let binary = hash[offset..<offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } & 0x7fff_ffff
        let modulus = (0..<digits).reduce(UInt32(1)) { value, _ in value * 10 }
        let code = String(binary % modulus)
        return String(repeating: "0", count: digits - code.count) + code
    }

    private static func decodeBase32(_ value: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)
        var buffer: UInt32 = 0
        var bits = 0
        var result = Data()
        var padding = false
        for byte in value.uppercased().utf8 {
            if byte == 32 { continue }
            if byte == 61 { padding = true; continue }
            guard !padding, let index = alphabet.firstIndex(of: byte) else { return nil }
            buffer = (buffer << 5) | UInt32(index)
            bits += 5
            if bits >= 8 {
                bits -= 8
                result.append(UInt8((buffer >> bits) & 255))
            }
        }
        guard bits < 5, buffer & ((1 << bits) - 1) == 0 else { return nil }
        return result
    }
}
