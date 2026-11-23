import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite(.serialized) struct TemplateTests {
    private func fixture() throws -> Data {
        try Data(contentsOf: TestEnv.fixtures.appending(path: "package-index/real-index-2026-11-17.json"))
    }

    private func tmp() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "typstcore-tpl-\(UUID().uuidString)")
    }

    @Test func catalogFromRealIndex() async throws {
        let rt = try await TestEnv.runtime(packageIndex: try fixture())
        let list = await rt.templates()
        // 912 = distinct names with a `template` object and compiler <= 0.15.1, computed with `python3 -I` over the fixture.
        #expect(list.count == 912)
        #expect(list.map(\.name) == list.map(\.name).sorted())
        let ieee = try #require(list.first { $0.name == "charged-ieee" })
        #expect(ieee.version == "0.1.4")   // highest compatible version in the fixture
        #expect(ieee.path == "template" && ieee.entrypoint == "main.typ")
        #expect(ieee.spec == "@preview/charged-ieee:0.1.4")
        #expect(ieee.thumbnailURL.absoluteString == "https://packages.typst.org/preview/thumbnails/charged-ieee-0.1.4-small.webp")
    }

    private func localTemplateRuntime() async throws -> (TypstRuntime, URL) {
        let rt = try await TestEnv.runtime(packageIndex: Data("[]".utf8))
        let pkgs = tmp()
        let pkg = pkgs.appending(path: "preview/tpl-demo/0.1.0")
        let fm = FileManager.default
        try fm.createDirectory(at: pkg.appending(path: "template/sub"), withIntermediateDirectories: true)
        try """
        [package]
        name = "tpl-demo"
        version = "0.1.0"
        entrypoint = "lib.typ"

        [template]
        path = "template"
        entrypoint = "main.typ"
        """.write(to: pkg.appending(path: "typst.toml"), atomically: true, encoding: .utf8)
        for f in ["template/main.typ", "template/refs.bib", "template/sub/x.typ"] {
            try f.write(to: pkg.appending(path: f), atomically: true, encoding: .utf8)
        }
        rt.setPackagesDir(pkgs)
        return (rt, pkgs)
    }

    private let demo = PackageTemplate(name: "tpl-demo", version: "0.1.0", description: "", authors: [], categories: [],
                                       path: "template", entrypoint: "main.typ")

    @Test func createProjectCopiesTemplateDirectory() async throws {
        let (rt, _) = try await localTemplateRuntime()
        let dest = tmp()
        let main = try await rt.createProject(from: demo, at: dest)
        #expect(main.raw == "main.typ")
        let files = try #require(FileManager.default.enumerator(atPath: dest.path)).allObjects.compactMap { $0 as? String }
            .filter { !$0.hasSuffix("sub") }.sorted()
        #expect(files == ["main.typ", "refs.bib", "sub/x.typ"])
    }

    @Test func existingDestinationIsLeftAlone() async throws {
        let (rt, _) = try await localTemplateRuntime()
        let dest = tmp()
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try "keep".write(to: dest.appending(path: "mine.txt"), atomically: true, encoding: .utf8)
        await #expect(throws: TemplateError.destinationExists(dest.lastPathComponent)) {
            try await rt.createProject(from: demo, at: dest)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dest.path) == ["mine.txt"])
        #expect(try String(contentsOf: dest.appending(path: "mine.txt"), encoding: .utf8) == "keep")
    }

    // Deterministic offline too: a name that does not exist 404s, an unreachable network fails; both are .fetchFailed.
    @Test func unresolvableSpecFailsWithoutCreatingFolder() async throws {
        let rt = try await TestEnv.runtime(packageIndex: Data("[]".utf8))
        let dest = tmp()
        let t = PackageTemplate(name: "no-such-package-tympan-test", version: "0.0.1", description: "", authors: [],
                                categories: [], path: "template", entrypoint: "main.typ")
        do {
            _ = try await rt.createProject(from: t, at: dest)
            Issue.record("expected a throw")
        } catch {
            guard case .fetchFailed(let m) = error else { Issue.record("wrong error \(error)"); return }
            #expect(!m.isEmpty)
        }
        #expect(!FileManager.default.fileExists(atPath: dest.path))
    }
}
