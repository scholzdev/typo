import Sparkle
import SwiftUI

/// Sparkle checks the appcast (`SUFeedURL` in Info.plist) once a day and offers new versions, signed with the key whose
/// public half is `SUPublicEDKey`. Debug builds never check: they share the release's bundle id.
@MainActor final class Updates {
    static let shared = Updates()
    let controller: SPUStandardUpdaterController

    private init() {
        #if DEBUG
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        #else
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        #endif
    }

    static var enabled: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }
}
