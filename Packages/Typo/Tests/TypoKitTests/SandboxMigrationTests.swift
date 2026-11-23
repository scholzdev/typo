import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@MainActor @Suite struct SandboxMigrationTests {
    let fm = FileManager.default
    func tmp() throws -> URL {
        let u = fm.temporaryDirectory.appending(path: "typstcore-mig-\(UUID().uuidString)")
        try fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    func write(_ s: String, _ u: URL) throws {
        try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(s.utf8).write(to: u)
    }
    func read(_ u: URL) -> String? { try? String(contentsOf: u, encoding: .utf8) }

    @Test func copiesMissingKeysAndFoldersWithoutOverwritingAndRunsOnce() throws {
        let container = try tmp(), home = try tmp()
        let prefs = container.appending(path: "Library/Preferences/x.plist")
        try fm.createDirectory(at: prefs.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["editorFontSize": 18, "editorTheme": "old"], format: .binary, options: 0).write(to: prefs)
        let sup = "Library/Application Support/"
        try write("snap", container.appending(path: sup + "Tympan/Snapshots/abc/1.json"))
        try write("theirs", container.appending(path: sup + "typst/packages/preview/a/0.1/typst.toml"))
        try write("new", container.appending(path: sup + "typst/packages/preview/a/0.1/other.typ"))
        try write("mine", home.appending(path: sup + "typst/packages/preview/a/0.1/typst.toml"))
        let suite = "typstcore-mig-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("kept", forKey: "editorTheme")

        SandboxMigration.run(container: container, home: home, prefs: prefs, defaults: defaults, fileManager: fm)
        #expect(defaults.integer(forKey: "editorFontSize") == 18)
        #expect(defaults.string(forKey: "editorTheme") == "kept")
        #expect(read(home.appending(path: sup + "Tympan/Snapshots/abc/1.json")) == "snap")
        #expect(read(home.appending(path: sup + "typst/packages/preview/a/0.1/typst.toml")) == "mine")
        #expect(read(home.appending(path: sup + "typst/packages/preview/a/0.1/other.typ")) == "new")
        #expect(read(container.appending(path: sup + "Tympan/Snapshots/abc/1.json")) == "snap")   // container untouched
        #expect(fm.fileExists(atPath: prefs.path))

        try write("later", container.appending(path: sup + "Tympan/late.json"))
        SandboxMigration.run(container: container, home: home, prefs: prefs, defaults: defaults, fileManager: fm)
        #expect(read(home.appending(path: sup + "Tympan/late.json")) == nil)
    }

    @Test func reopensByPathWhenTheBookmarkIsGarbage() async throws {
        let (_, root) = try await TestEnv.project(files: ["main.typ": "x"])
        let suite = "typstcore-mig-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let recents = RecentProjects(defaults: defaults)
        let id = try recents.register(root: root, main: RelPath("main.typ")!)
        recents.corruptBookmark(id)
        let p = try await Project.open(id, recents: recents)
        #expect(p.root.standardizedFileURL.path == root.standardizedFileURL.path)
        #expect(recents.record(id)?.bookmark != Data([1, 2, 3]))

        recents.corruptBookmark(id)
        try fm.removeItem(at: root)
        await #expect(throws: ProjectError.self) { _ = try await Project.open(id, recents: recents) }
    }
}

extension RecentProjects {
    func corruptBookmark(_ id: ProjectID) { setBookmarkForTesting(Data([1, 2, 3]), id) }
}
