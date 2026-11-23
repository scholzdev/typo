import CryptoKit
import Foundation

// Issues Typo license keys: <base64url(JSON payload)>.<base64url(Ed25519 signature)>, no padding.
// Run: swift tools/license.swift keygen | pubkey | issue <email>
// The private key lives outside the repo at ~/.config/tympan/license-signing.key (raw 32 bytes, base64).
let dir = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/tympan")
let keyFile = dir.appending(path: "license-signing.key")

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func loadKey() -> Curve25519.Signing.PrivateKey {
    guard let text = try? String(contentsOf: keyFile, encoding: .utf8),
          let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else { fail("No valid signing key at \(keyFile.path); run keygen.", 1) }
    return key
}

func base64url(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

struct License: Codable {
    var id: String
    var email: String
    var issued: Int
}

let args = CommandLine.arguments.dropFirst()
switch (args.first, args.count) {
case ("keygen", 1):
    if FileManager.default.fileExists(atPath: keyFile.path) { fail("\(keyFile.path) already exists; refusing to overwrite.", 1) }
    let key = Curve25519.Signing.PrivateKey()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    guard FileManager.default.createFile(atPath: keyFile.path, contents: Data(key.rawRepresentation.base64EncodedString().utf8), attributes: [.posixPermissions: 0o600]) else { fail("Couldn’t write \(keyFile.path).", 1) }
    print(key.publicKey.rawRepresentation.base64EncodedString())
case ("pubkey", 1):
    print(loadKey().publicKey.rawRepresentation.base64EncodedString())
case ("issue", 2):
    let license = License(id: UUID().uuidString, email: args.last!, issued: Int(Date().timeIntervalSince1970))
    let payload = try JSONEncoder().encode(license)
    print(base64url(payload) + "." + base64url(try loadKey().signature(for: payload)))
default:
    fail("usage: swift tools/license.swift keygen | pubkey | issue <email>", 2)
}
