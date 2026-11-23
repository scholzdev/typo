import Foundation
import Observation
import TypoKit
import TypstEngine

/// Installed `@preview` packages with a newer version in the cached index, and the downloads that bring them up to date.
@MainActor @Observable final class PackageUpdateModel {
    private(set) var installed: [String: Set<String>] = [:]
    private(set) var updates: [PackageUpdate] = []
    private(set) var installing = Set<String>()     // package names
    private(set) var errors: [String: String] = [:]

    func refresh() async {
        let dir = TypstRuntime.packageDirectory
        let found = await Task.detached { PackageUpdates.installed(in: dir) }.value
        let index = await TypstRuntime.universePackages()
        installed = found
        updates = PackageUpdates.available(installed: found, index: index)
    }

    /// Downloads the newer version into the package cache; documents keep importing what they import.
    func update(_ u: PackageUpdate) async {
        guard installing.insert(u.name).inserted else { return }
        errors[u.name] = nil
        do { _ = try await TypstRuntime.shared.value.install(name: u.name, version: u.newest) }
        catch { errors[u.name] = error.localizedDescription }
        installing.remove(u.name)
        await refresh()
    }

    func updateAll() async {
        for u in updates { await update(u) }
    }
}
