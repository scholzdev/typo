import CryptoKit
import Foundation

public struct License: Codable, Equatable, Sendable {
    public var id: String
    public var email: String
    public var issued: Date

    public init(id: String, email: String, issued: Date) {
        self.id = id
        self.email = email
        self.issued = issued
    }

    /// The matching private key never ships; `tools/license.swift` signs with it.
    public static let publicKey = try! Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: "+l3xs/MXqJvbIQyNbfKHKdALN/Fy0iynzBb4uWK2Bwk=")!)

    /// A key is `<base64url(JSON payload)>.<base64url(Ed25519 signature)>`; the signature covers the payload bytes as sent.
    public static func verify(_ key: String, publicKey: Curve25519.Signing.PublicKey = License.publicKey) -> License? {
        verifySigned(key, publicKey: publicKey)
    }
}

/// Proof from the license server that a key is active on one device; same encoding as a license key.
public struct Activation: Codable, Equatable, Sendable {
    public var license: String
    public var device: String
    public var expires: Date

    public init(license: String, device: String, expires: Date) {
        self.license = license
        self.device = device
        self.expires = expires
    }

    public static let publicKey = try! Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: "ra0jGCWv9GFOa3sN6lghtNL+ft4l7motrbKy3VZtihc=")!)

    public static func verify(_ token: String, publicKey: Curve25519.Signing.PublicKey = Activation.publicKey) -> Activation? {
        verifySigned(token, publicKey: publicKey)
    }
}

private func verifySigned<T: Decodable>(_ string: String, publicKey: Curve25519.Signing.PublicKey) -> T? {
    func decode(_ s: Substring) -> Data? {
        var b64 = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        return Data(base64Encoded: b64)
    }
    let parts = string.filter { !$0.isWhitespace }.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 2, let payload = decode(parts[0]), let signature = decode(parts[1]),
          publicKey.isValidSignature(signature, for: payload) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return try? decoder.decode(T.self, from: payload)
}

public enum LicenseState: Equatable, Sendable {
    case licensed(License)
    case trial(daysLeft: Int)   // 1...trialDays
    case expired

    public static let trialDays = 14

    public static func evaluate(license: License?, activation: Activation?, device: String, firstLaunch: Date, now: Date) -> LicenseState {
        if let license, let activation, activation.license == license.id, activation.device == device, activation.expires > now { return .licensed(license) }
        let elapsed = now.timeIntervalSince(firstLaunch)
        if elapsed < -86400 { return .expired }   // clock set back more than a day
        let daysLeft = trialDays - Int(max(elapsed, 0) / 86400)
        return daysLeft >= 1 ? .trial(daysLeft: daysLeft) : .expired
    }
}
