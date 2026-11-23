import Foundation
import Combine

/// Bumps `revision` after any UserDefaults change, so EditorView re-runs updateNSView.
@MainActor final class EditorSettingsObserver: ObservableObject {   // ObservableObject: an NSViewRepresentable reliably updates on @ObservedObject
    static let shared = EditorSettingsObserver()
    @Published private(set) var revision = 0
    private var pending = false

    private init() {
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule() }
        }
    }

    private func schedule() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async { [self] in
            pending = false
            revision += 1
        }
    }
}
