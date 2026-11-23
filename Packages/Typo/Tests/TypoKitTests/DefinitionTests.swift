import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite(.serialized) @MainActor struct DefinitionTests {
    static let main = RelPath("main.typ")!

    static func project(_ files: [String: String]) async throws -> (Project, Buffer) {
        let (p, _) = try await TestEnv.project(files: files)
        let b = try await p.open(main)
        _ = await p.settle()
        return (p, b)
    }

    @Test func crossFileImport() async throws {
        let (p, b) = try await Self.project(["lib.typ": "#let greet(n) = [Hi #n]\n", "main.typ": "#import \"lib.typ\": greet\n#greet[x]\n"])
        let use = (b.storage.string as NSString).range(of: "greet[").location
        #expect(await p.definition(in: Self.main, at: use + 1) == .source(RelPath("lib.typ")!, NSRange(location: 5, length: 5)))
    }

    /// The compiler may stop at the import item; the binding index then follows it into the imported file (what Jump to Definition does).
    @Test(arguments: ["#f\n", "#f(1)\n", "#f[x]\n", "#{ f(1) }\n"])
    func importedUseFollowsIntoTheDefiningFile(use: String) async throws {
        let (p, b) = try await Self.project(["lib.typ": "#let f(x) = x\n", "main.typ": "#import \"lib.typ\": f\n" + use])
        let at = (b.storage.string as NSString).range(of: "f", options: .backwards).location
        guard case .source(let file, let range) = await p.definition(in: Self.main, at: at) else { Issue.record("no source definition"); return }
        let followed = await p.bindingIndex().symbol(in: file, at: range.location)
        #expect(followed?.file == RelPath("lib.typ")! && followed?.defRange == NSRange(location: 5, length: 1))
    }

    @Test func importPathIsAFile() async throws {
        let (p, b) = try await Self.project(["lib.typ": "#let a = 1\n", "main.typ": "#import \"lib.typ\": a\n"])
        let at = (b.storage.string as NSString).range(of: "lib.typ").location + 2
        #expect(await p.definition(in: Self.main, at: at) == .file(RelPath("lib.typ")!))
    }

    @Test func localDefinitionSeesUnsavedText() async throws {
        let (p, b) = try await Self.project(["main.typ": "#let v = 1\n#v\n"])
        replace(b, NSRange(location: 0, length: 0), with: "// c\n")
        let use = (b.storage.string as NSString).range(of: "#v").location + 1
        #expect(await p.definition(in: Self.main, at: use) == .source(Self.main, NSRange(location: 10, length: 1)))
    }

    @Test func standardLibraryIsBuiltin() async throws {
        let (p, b) = try await Self.project(["main.typ": "#text(red)[a]\n"])
        _ = b
        guard case .builtin(let doc)? = await p.definition(in: Self.main, at: 2) else { Issue.record("not builtin"); return }
        #expect(doc.name == "text")
        #expect(doc.docs.contains("text"))
        #expect(doc.url == URL(string: "https://typst.app/docs/reference/text/text/"))
    }

    @Test func builtinURLs() async throws {
        let (p, _) = try await Self.project(["main.typ": "#calc.max(1, 2)\n#heading[a]\n#table()\n#int(1)\n"])
        func url(_ at: Int) async -> String? {
            guard case .builtin(let d)? = await p.definition(in: Self.main, at: at) else { return nil }
            return d.url?.absoluteString
        }
        #expect(await url(7) == "https://typst.app/docs/reference/foundations/calc/#functions-max")
        #expect(await url(17) == "https://typst.app/docs/reference/model/heading/")
        #expect(await url(29) == "https://typst.app/docs/reference/model/table/")
        #expect(await url(38) == "https://typst.app/docs/reference/foundations/int/")
    }

    /// Quick Help shows every parameter with its types, for built-ins and the project's own functions.
    @Test func signatureListsEveryParameter() async throws {
        let (p, _) = try await Self.project(["main.typ": "#let greet(name, loud: false) = name\n#figure(caption: [c])[x]\n#greet[a]\n#calc.max(1, 2)\n"])
        let text = p.buffer(for: Self.main)?.storage.string as NSString? ?? ""
        let fig = await p.signature(in: Self.main, at: text.range(of: "figure").location + 2) ?? ""
        #expect(fig.hasPrefix("figure(\n  body: content,\n  alt: none | str,"), "\(fig)")
        #expect(fig.contains("  numbering: none | str | function,"), "\(fig)")
        let greet = await p.signature(in: Self.main, at: text.range(of: "greet[").location + 2)
        #expect(greet == "greet(\n  name,\n  loud: false\n)")
        let max = await p.signature(in: Self.main, at: text.range(of: "max").location + 1) ?? ""
        #expect(max.hasPrefix("max(\n  ..values:"), "\(max)")
    }

    @Test func nothingUnderThePlainText() async throws {
        let (p, _) = try await Self.project(["main.typ": "just words\n"])
        #expect(await p.definition(in: Self.main, at: 3) == nil)
    }
}
