import CryptoKit
import IOKit
import SwiftUI
import TypoKit

extension SettingsKey {
    static let licenseKey = "licenseKey"
    static let firstLaunch = "licenseFirstLaunch"
    static let activationToken = "licenseActivationToken"
}

enum LicenseError: Error {
    case invalid, revoked, deviceLimit, network

    var message: String {
        switch self {
        case .invalid: "That license key isn\u{2019}t valid."
        case .revoked: "This license has been revoked."
        case .deviceLimit: "This license is already active on 3 Macs. Deactivate one of them first."
        case .network: "Couldn\u{2019}t reach the license server. Check your connection and try again."
        }
    }
}

private struct LicenseReply: Decodable {
    var token: String?
    var error: String?
}

@MainActor @Observable final class LicenseStore {
    static let shared = LicenseStore()
    /// Off for now: no License settings tab, no trial banner, never read-only. Flip to turn licensing back on.
    static let enforced = false
    private(set) var license: License?
    private(set) var activation: Activation?
    private let firstLaunch: Date
    private let device: String
    var state: LicenseState { LicenseState.evaluate(license: license, activation: activation, device: device, firstLaunch: firstLaunch, now: Date()) }
    var readOnly: Bool { Self.enforced && state == .expired }

    private init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }
        let uuid = IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String ?? ""
        device = SHA256.hash(data: Data(("tympan-device:" + uuid).utf8)).map { String(format: "%02x", $0) }.joined()
        let d = UserDefaults.standard
        license = d.string(forKey: SettingsKey.licenseKey).flatMap { License.verify($0) }
        activation = d.string(forKey: SettingsKey.activationToken).flatMap { Activation.verify($0) }
        // shortcut: UserDefaults is user-resettable, move to server-side trial start with online activation
        if d.object(forKey: SettingsKey.firstLaunch) == nil { d.set(Date().timeIntervalSince1970, forKey: SettingsKey.firstLaunch) }
        firstLaunch = Date(timeIntervalSince1970: d.double(forKey: SettingsKey.firstLaunch))
        if license != nil, let activation, activation.expires.timeIntervalSinceNow < 29 * 86400 { Task { await refresh() } }
    }

    func activate(_ key: String) async -> LicenseError? {
        let key = key.filter { !$0.isWhitespace }
        guard let verified = License.verify(key) else { return .invalid }
        guard let r = await post("/v1/activate", key: key) else { return .network }
        if r.status == 403 {
            switch r.reply?.error {
            case "invalid": return .invalid
            case "revoked": return .revoked
            case "device_limit": return .deviceLimit
            default: return .network
            }
        }
        guard r.status == 200, let token = r.reply?.token else { return .network }
        guard let verifiedToken = Activation.verify(token), verifiedToken.device == device, verifiedToken.license == verified.id else { return .invalid }
        UserDefaults.standard.set(key, forKey: SettingsKey.licenseKey)
        UserDefaults.standard.set(token, forKey: SettingsKey.activationToken)
        license = verified
        activation = verifiedToken
        return nil
    }

    func deactivate() async -> LicenseError? {
        let d = UserDefaults.standard
        if let key = d.string(forKey: SettingsKey.licenseKey) {
            guard let r = await post("/v1/deactivate", key: key), r.status == 200 || r.status == 403 else { return .network }
        }
        d.removeObject(forKey: SettingsKey.licenseKey)
        d.removeObject(forKey: SettingsKey.activationToken)
        license = nil
        activation = nil
        return nil
    }

    private func refresh() async {
        guard let key = UserDefaults.standard.string(forKey: SettingsKey.licenseKey), let r = await post("/v1/activate", key: key) else { return }
        if r.status == 200, let token = r.reply?.token, let fresh = Activation.verify(token), fresh.device == device, fresh.license == license?.id {
            UserDefaults.standard.set(token, forKey: SettingsKey.activationToken)
            activation = fresh
        } else if r.status == 403, r.reply?.error == "revoked" || r.reply?.error == "invalid" {
            UserDefaults.standard.removeObject(forKey: SettingsKey.activationToken)
            activation = nil
        }
    }

    /// nil means the request never completed.
    private func post(_ path: String, key: String) async -> (status: Int, reply: LicenseReply?)? {
        var request = URLRequest(url: URL(string: "https://license.florianscholz.me" + path)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["key": key, "device": device])
        guard let (data, response) = try? await URLSession.shared.data(for: request), let http = response as? HTTPURLResponse else { return nil }
        return (http.statusCode, try? JSONDecoder().decode(LicenseReply.self, from: data))
    }
}

struct LicenseBanner: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if LicenseStore.shared.readOnly {
            HStack {
                Label("Your trial has ended. Documents are read-only; exporting still works.", systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                Spacer()
                Button("Enter License…") {
                    UserDefaults.standard.set("license", forKey: SettingsKey.tab)
                    openSettings()
                }
                .buttonStyle(.glassProminent)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .padding(.horizontal, 8).padding(.top, 8)
        }
    }
}
