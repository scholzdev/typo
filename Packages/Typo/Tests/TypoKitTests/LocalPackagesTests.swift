import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite(.serialized) @MainActor struct LocalPackagesTests {
    /// `<tmp>/local/mypkg/0.1.0/{typst.toml, lib.typ}`; `body` is lib.typ.
    private func dataDir(_ body: String = "#let greet() = [Hello from mypkg]", description: String = "My local package",
                         compiler: String? = nil) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "typstcore-data-\(UUID().uuidString)")
        let pkg = dir.appending(path: "local/mypkg/0.1.0")
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        let bound = compiler.map { "compiler = \"\($0)\"\n" } ?? ""
        try """
        [package]
        name = "mypkg"
        version = "0.1.0"
        entrypoint = "lib.typ"
        description = "\(description)"
        \(bound)
        """.write(to: pkg.appending(path: "typst.toml"), atomically: true, encoding: .utf8)
        try body.write(to: pkg.appending(path: "lib.typ"), atomically: true, encoding: .utf8)
        return dir
    }

    private func runtime() async throws -> TypstRuntime {
        try await TestEnv.runtime(packageIndex: Data(#"[{"name":"cetz","version":"0.4.2","description":"Drawing"}]"#.utf8))
    }

    private static let usage = "#import \"@local/mypkg:0.1.0\": greet\n#greet()"

    /// Polls: a package change reaches open projects through a stream, so the recompile lands slightly later.
    private func eventually(_ p: Project, _ ok: (Project) -> Bool) async -> Bool {
        for _ in 0..<100 {
            _ = await p.settle()
            if ok(p) { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    private func missing(_ p: Project) -> Bool {
        p.diagnostics.contains { $0.severity == .error && $0.message.contains("package not found") }
    }

    private func text(_ p: Project) async -> String {
        guard let r = await p.settle(), let pdf = await r.snapshot.pdf() else { return "" }
        return TestEnv.pdfText(pdf)
    }

    @Test func importResolvesOnlyWithTheDataDir() async throws {
        let rt = try await runtime()
        let (p, _) = try await TestEnv.project(files: ["main.typ": Self.usage], runtime: rt)
        #expect(await eventually(p, missing))
        #expect(rt.setPackagesDir(try dataDir()) == 1)
        #expect(await eventually(p) { !self.missing($0) && !$0.diagnostics.contains { $0.severity == .error } })
        #expect(await text(p) == "Hello from mypkg")
    }

    @Test func switchingTheDirReResolvesWithoutStaleResults() async throws {
        let rt = try await runtime()
        let (p, _) = try await TestEnv.project(files: ["main.typ": Self.usage], runtime: rt)
        let b = try await p.open(RelPath("main.typ")!)
        rt.setPackagesDir(try dataDir("#let greet() = [One]"))
        #expect(await eventually(p) { !self.missing($0) })
        #expect(await text(p) == "One")

        rt.setPackagesDir(nil)
        #expect(await eventually(p, missing))

        rt.setPackagesDir(try dataDir("#let greet() = [Two]"))
        #expect(await eventually(p) { !self.missing($0) })
        #expect(await text(p) == "Two")

        // Overlays stay exact across the switches, and edits still compile against the current dir.
        type(b, "\n#greet()")
        #expect(await text(p) == "Two Two")
        #expect(b.storage.string == Self.usage + "\n#greet()")
        #expect(await p.engine.overlayText(b.path) == b.storage.string)
        rt.setPackagesDir(nil)
    }

    @Test func completionListsLocalPackagesAlongsidePreview() async throws {
        let rt = try await runtime()
        rt.setPackagesDir(try dataDir())
        let (p, _) = try await TestEnv.project(files: ["main.typ": "#import \"@local/\"\n#import \"@\""], runtime: rt)
        let b = try await p.open(RelPath("main.typ")!)
        let local = try #require(await p.complete(in: b.path, at: 16, explicit: false))
        let item = try #require(local.items.first { $0.kind == .package && $0.label == "\"@local/mypkg:0.1.0\"" })
        #expect(item.detail == "My local package")
        let all = try #require(await p.complete(in: b.path, at: b.storage.length - 1, explicit: false))
        #expect(Set(all.items.filter { $0.kind == .package }.map(\.label)) == ["\"@local/mypkg:0.1.0\"", "\"@preview/cetz:0.4.2\""])
        rt.setPackagesDir(nil)
        let gone = try #require(await p.complete(in: b.path, at: b.storage.length - 1, explicit: false))
        #expect(gone.items.filter { $0.kind == .package }.map(\.label) == ["\"@preview/cetz:0.4.2\""])
    }

    @Test func incompatibleLocalPackagesAreSkipped() async throws {
        let rt = try await runtime()
        #expect(rt.setPackagesDir(try dataDir(compiler: "99.0.0")) == 0)
        rt.setPackagesDir(nil)
    }

    @Test func bookmarkRoundTripAndStaleRefresh() async throws {
        let suite = "typstcore-bookmark-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let rt = try await runtime()
        let dir = try dataDir()
        let f = LocalPackagesFolder(defaults: defaults, runtime: rt)
        try await f.choose(dir)
        #expect(f.url?.standardizedFileURL.resolvingSymlinksInPath() == dir.standardizedFileURL.resolvingSymlinksInPath())

        // A fresh instance (next launch) restores from the stored bookmark and applies it.
        let (p, _) = try await TestEnv.project(files: ["main.typ": Self.usage], runtime: rt)
        rt.setPackagesDir(nil)
        #expect(await eventually(p, missing))
        let g = LocalPackagesFolder(defaults: defaults, runtime: rt)
        await g.restore()
        #expect(g.url != nil)
        #expect(await eventually(p) { !self.missing($0) })

        // Moving the folder makes the bookmark stale (it still resolves); restore rewrites it.
        let moved = dir.deletingLastPathComponent().appending(path: "moved-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: dir, to: moved)
        let before = defaults.data(forKey: "TypstCore.localPackagesBookmark")
        let h = LocalPackagesFolder(defaults: defaults, runtime: rt)
        await h.restore()
        #expect(h.url?.resolvingSymlinksInPath().path == moved.resolvingSymlinksInPath().path)
        #expect(defaults.data(forKey: "TypstCore.localPackagesBookmark") != before)

        await h.clear()
        #expect(h.url == nil && defaults.data(forKey: "TypstCore.localPackagesBookmark") == nil)
        #expect(await eventually(p, missing))
        await LocalPackagesFolder(defaults: defaults, runtime: rt).restore()   // nothing stored: no-op
    }
}
