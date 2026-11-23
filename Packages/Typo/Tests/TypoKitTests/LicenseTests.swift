import CryptoKit
import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit

private func b64url(_ d: Data) -> String {
    d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

private let payload = Data(#"{"id":"1B4E28BA-2FA1-11D2-883F-0016D3CCA427","email":"a@example.com","issued":1795390000}"#.utf8)

private func key(_ payload: Data = payload, signedBy signer: Curve25519.Signing.PrivateKey) -> String {
    b64url(payload) + "." + b64url(try! signer.signature(for: payload))
}

@Test func verifyRoundTripsAKey() {
    let signer = Curve25519.Signing.PrivateKey()
    let license = License.verify(key(signedBy: signer), publicKey: signer.publicKey)
    #expect(license == License(id: "1B4E28BA-2FA1-11D2-883F-0016D3CCA427", email: "a@example.com", issued: Date(timeIntervalSince1970: 1795390000)))
}

@Test func verifyIgnoresPastedWhitespace() {
    let signer = Curve25519.Signing.PrivateKey()
    let k = key(signedBy: signer)
    let mid = k.index(k.startIndex, offsetBy: 20)
    let pasted = " \n" + k[..<mid] + "\n  " + k[mid...] + "\n"
    #expect(License.verify(pasted, publicKey: signer.publicKey) != nil)
}

@Test func verifyRejectsATamperedPayloadOrForeignSignature() {
    let signer = Curve25519.Signing.PrivateKey()
    var changed = payload
    changed[changed.count - 3] ^= 1
    let signature = b64url(try! signer.signature(for: payload))
    #expect(License.verify(b64url(changed) + "." + signature, publicKey: signer.publicKey) == nil)
    #expect(License.verify(key(signedBy: Curve25519.Signing.PrivateKey()), publicKey: signer.publicKey) == nil)
}

@Test func verifyRejectsMalformedKeys() {
    let signer = Curve25519.Signing.PrivateKey()
    let k = key(signedBy: signer)
    for bad in ["", "garbage", "!!!.???", k.split(separator: ".")[0].description, k + ".AAAA"] {
        #expect(License.verify(bad, publicKey: signer.publicKey) == nil)
    }
}

private let start = Date(timeIntervalSince1970: 1_000_000)
private let license = License(id: "x", email: "a@example.com", issued: Date(timeIntervalSince1970: 0))

private func activation(license: String = "x", device: String = "dev", expiresIn days: Double = 30) -> Activation {
    Activation(license: license, device: device, expires: start.addingTimeInterval(days * 86400))
}

private func state(_ a: Activation?, afterDays d: Double = 0) -> LicenseState {
    .evaluate(license: license, activation: a, device: "dev", firstLaunch: start, now: start.addingTimeInterval(d * 86400))
}

@Test func activationRoundTripsAndRejectsAForeignKey() {
    let signer = Curve25519.Signing.PrivateKey()
    let p = Data(#"{"license":"x","device":"dev","expires":1000000}"#.utf8)
    #expect(Activation.verify(key(p, signedBy: signer), publicKey: signer.publicKey) == Activation(license: "x", device: "dev", expires: Date(timeIntervalSince1970: 1_000_000)))
    #expect(Activation.verify(key(p, signedBy: Curve25519.Signing.PrivateKey()), publicKey: signer.publicKey) == nil)
}

@Test func trialCountsDownAndExpires() {
    func state(afterDays d: Double) -> LicenseState { .evaluate(license: nil, activation: nil, device: "dev", firstLaunch: start, now: start.addingTimeInterval(d * 86400)) }
    #expect(state(afterDays: 0) == .trial(daysLeft: 14))
    #expect(state(afterDays: 13.5) == .trial(daysLeft: 1))
    #expect(state(afterDays: 14) == .expired)
    #expect(state(afterDays: -2) == .expired)
}

@Test func aLicenseWithAMatchingActivationOverridesTheTrial() {
    #expect(state(activation(expiresIn: 200), afterDays: 100) == .licensed(license))
    #expect(state(activation(expiresIn: 200), afterDays: -5) == .licensed(license))
}

@Test func aLicenseWithoutAMatchingLiveActivationFallsBackToTheTrial() {
    #expect(state(nil) == .trial(daysLeft: 14))
    #expect(state(activation(device: "other")) == .trial(daysLeft: 14))
    #expect(state(activation(license: "other")) == .trial(daysLeft: 14))
    #expect(state(activation(expiresIn: 5), afterDays: 6) == .trial(daysLeft: 8))
    #expect(state(activation(expiresIn: 5), afterDays: 20) == .expired)
}
