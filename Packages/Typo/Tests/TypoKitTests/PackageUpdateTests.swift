import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite struct PackageUpdateTests {
    static let index = Universe.parse(Data("""
    [{"name":"cetz","version":"0.3.0"},{"name":"cetz","version":"0.4.1"},{"name":"cetz","version":"0.10.0"},{"name":"cetz","version":"0.9.9"},
     {"name":"fresh","version":"1.0.0"},{"name":"fresh","version":"2.0.0","compiler":"0.99.0"},
     {"name":"same","version":"1.0.0"},{"name":"pre","version":"1.0.0"},{"name":"pre","version":"1.1.0-rc1"}]
    """.utf8))

    @Test func semverCompare() {
        #expect(PackageUpdates.isNewer("0.10.0", than: "0.9.9"))
        #expect(!PackageUpdates.isNewer("0.9.9", than: "0.10.0"))
        #expect(!PackageUpdates.isNewer("1.0.0", than: "1.0.0"))
        #expect(PackageUpdates.isNewer("1.0.1-rc1", than: "1.0.0"))      // suffix ignored
        #expect(!PackageUpdates.isNewer("1.0.0-rc1", than: "1.0.0"))
        #expect(!PackageUpdates.isNewer("garbage", than: "1.0.0"))
    }

    @Test func scansPreviewOnly() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        for p in ["preview/cetz/0.3.0", "preview/cetz/0.4.1", "local/tool/1.0.0"] {
            try fm.createDirectory(at: root.appending(path: p), withIntermediateDirectories: true)
        }
        try Data("{}".utf8).write(to: root.appending(path: "preview/index.json"))
        #expect(PackageUpdates.installed(in: root) == ["cetz": ["0.3.0", "0.4.1"]])
        #expect(PackageUpdates.installed(in: root.appending(path: "missing")).isEmpty)
    }

    @Test func detectsUpdatesAndSkipsTooNewTypst() {
        let installed: [String: Set<String>] = ["cetz": ["0.3.0", "0.4.1"], "fresh": ["1.0.0"], "same": ["1.0.0"], "pre": ["1.0.0"], "gone": ["1.0.0"]]
        let u = PackageUpdates.available(installed: installed, index: Self.index, ours: "0.15.1")
        // 0.10.0 beats 0.9.9; fresh 2.0.0 needs Typst 0.99; "1.1.0-rc1" parses as 1.1.0 (the index has none in practice)
        #expect(u.map { "\($0.name) \($0.installed)->\($0.newest)" } == ["cetz 0.4.1->0.10.0", "pre 1.0.0->1.1.0-rc1"])
        #expect(PackageUpdates.available(installed: ["fresh": ["1.0.0"]], index: Self.index, ours: "1.0.0").map(\.newest) == ["2.0.0"])
    }

    static func f(_ s: String) -> RelPath { RelPath(s)! }

    @Test func hintsOutdatedImportsOnly() {
        let text = "#import \"@preview/cetz:0.3.0\": canvas\n#import \"@preview/cetz:0.10.0\"\n#let x = read(\"@preview/cetz:0.1.0\")\n#import \"@preview/fresh:1.0.0\": *\n"
        let h = PackageUpdates.hints(sources: [(Self.f("a.typ"), text)], index: Self.index, ours: "0.15.1")
        #expect(h.map(\.message) == ["Newer version 0.10.0 of @preview/cetz is available"])
        #expect(h.allSatisfy { $0.severity == .hint })
        guard case .project(let loc) = h[0].origin else { Issue.record("origin"); return }
        #expect((text as NSString).substring(with: loc.range) == "\"@preview/cetz:0.3.0\"")
    }

    @Test func fixRewritesVersion() {
        let a = "#import \"@preview/cetz:0.3.0\": canvas\n", b = "#import \"@preview/cetz:0.3.0\": *\n#import \"@preview/cetz:0.4.1\"\n"
        let sources = [(Self.f("a.typ"), a), (Self.f("b.typ"), b)]
        let h = PackageUpdates.hints(sources: sources, index: Self.index, ours: "0.15.1")
        guard case .project(let loc) = h[0].origin, let u = PackageUpdates.parseHint(h[0].message) else { Issue.record("hint"); return }
        #expect(u.name == "cetz" && u.version == "0.10.0")
        let fixes = PackageUpdates.fixes(name: u.name, to: u.version, at: loc, sources: sources)
        #expect(fixes.map(\.title) == ["Update to 0.10.0", "Update All Imports of cetz to 0.10.0"])
        func apply(_ fix: QuickFix, _ file: String, _ text: String) -> String {
            (fix.edits[Self.f(file)] ?? []).sorted { $0.range.location > $1.range.location }
                .reduce(text as NSString) { $0.replacingCharacters(in: $1.range, with: $1.text) as NSString } as String
        }
        #expect(apply(fixes[0], "a.typ", a) == "#import \"@preview/cetz:0.10.0\": canvas\n")
        #expect(apply(fixes[0], "b.typ", b) == b)
        #expect(apply(fixes[1], "b.typ", b) == "#import \"@preview/cetz:0.10.0\": *\n#import \"@preview/cetz:0.4.1\"\n")
    }

    @Test @MainActor func quickFixesThroughProject() async throws {
        let text = "#import \"@preview/cetz:0.3.0\": canvas\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": text])
        _ = try await p.open(RelPath("main.typ")!)
        let d = Diagnostic(id: 0, severity: .hint, message: "Newer version 0.4.1 of @preview/cetz is available", hints: [],
                           origin: .project(Location(file: Self.f("main.typ"), range: NSRange(location: 8, length: 21))))
        #expect(QuickFixes.mayFix(d))
        #expect(await p.quickFixes(for: d).map(\.title) == ["Update to 0.4.1"])
    }
}
