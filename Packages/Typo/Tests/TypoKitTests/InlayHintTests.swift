import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite struct InlayCandidateTests {
    private func candidates(_ text: String) -> [String] {
        InlayHints.candidates(in: text, syntax: SyntaxMirror(text)).map { (text as NSString).substring(with: $0) }
    }

    @Test func nestedCallsYieldTheirOwnArguments() {
        #expect(candidates("#f(g(1, 2), 3)") == ["g(1, 2)", "3", "1", "2"])
    }

    @Test func namedSpreadAndContentArgumentsAreSkipped() {
        #expect(candidates("#f(a, key: b, c, ..xs, [d])[e]") == ["a", "c"])
        #expect(candidates("#f(a, key: b)") == [])                 // one positional argument is no hint
    }

    @Test func showRuleSelectorIsNoCall() {
        #expect(candidates("#show heading: it => it\n#show figure.where(kind: \"x\"): it => it") == [])
    }

    @Test func methodCalls() {
        #expect(candidates("#calc.pow(2, 3)") == ["2", "3"])
    }

    @Test func argumentAtTheStartOfALineHasNoGap() {
        #expect(candidates("#f(\na,\n  b)") == ["b"])
    }
}

@Suite(.serialized) @MainActor struct InlayHintTests {
    static let main = RelPath("main.typ")!

    /// The hints of `text` as `label@argument`, in text order.
    private func hints(_ text: String, files: [String: String] = [:], runtime: TypstRuntime? = nil) async throws -> [String] {
        let (p, _) = try await TestEnv.project(files: files.merging(["main.typ": text]) { a, _ in a }, runtime: runtime)
        _ = try await p.open(Self.main)
        _ = await p.settle()
        p.inlayHintsEnabled = true
        await p.runInlayHints()
        let ns = text as NSString
        return p.inlayHints(in: Self.main).sorted { $0.offset < $1.offset }.map { h in
            let end = ns.rangeOfCharacter(from: CharacterSet(charactersIn: ",)"), range: NSRange(location: h.offset, length: ns.length - h.offset)).location
            return h.label + "@" + ns.substring(with: NSRange(location: h.offset, length: end - h.offset))
        }
    }

    @Test func ownFunctionWithTwoPositionalParameters() async throws {
        let text = "#let f(base, exp) = base\n#f(2, 3)\n"
        #expect(try await hints(text) == ["base:@2", "exp:@3"])
        let (p, _) = try await TestEnv.project(files: ["main.typ": text])
        _ = try await p.open(Self.main)
        _ = await p.settle()
        p.inlayHintsEnabled = true
        await p.runInlayHints()
        let two = (text as NSString).range(of: "(2").location + 1
        #expect(p.inlayHints(in: Self.main).map(\.offset).sorted() == [two, two + 3])
    }

    @Test func builtinsImportsAndPackages() async throws {
        #expect(try await hints("#calc.pow(2, 3)\n#rgb(10, 20, 30)\n") == ["base:@2", "exponent:@3", "red:@10", "green:@20", "blue:@30"])
        #expect(try await hints("#import \"lib.typ\": h\n#h(1, 2)\n", files: ["lib.typ": "#let h(p, q) = p\n"]) == ["p:@1", "q:@2"])
        let data = FileManager.default.temporaryDirectory.appending(path: "typstcore-data-\(UUID().uuidString)")
        let pkg = data.appending(path: "local/mypkg/0.1.0")
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        try "[package]\nname = \"mypkg\"\nversion = \"0.1.0\"\nentrypoint = \"lib.typ\"\n".write(to: pkg.appending(path: "typst.toml"), atomically: true, encoding: .utf8)
        try "#let pair(left, right) = left\n".write(to: pkg.appending(path: "lib.typ"), atomically: true, encoding: .utf8)
        let rt = try await TestEnv.runtime(packageIndex: Data("[]".utf8))
        _ = rt.setPackagesDir(data)
        #expect(try await hints("#import \"@local/mypkg:0.1.0\": pair\n#pair(1, 2)\n", runtime: rt) == ["left:@1", "right:@2"])
    }

    @Test func namedArgumentsBetweenPositionalOnesKeepTheOrder() async throws {
        #expect(try await hints("#let k(a, key: 0, b) = a\n#k(1, key: 2, 3)\n") == ["a:@1", "b:@3"])
    }

    @Test func variadicParameterIsSilent() async throws {
        #expect(try await hints("#let v(x, y, ..r) = x\n#v(1, 2, 3)\n") == ["x:@1", "y:@2"])
        #expect(try await hints("#calc.max(1, 2)\n") == [])
    }

    @Test func underscoreParameterIsSilent() async throws {
        #expect(try await hints("#let g(_, b) = b\n#g(1, 2)\n") == ["b:@2"])
    }

    @Test func argumentNamedLikeTheParameterIsSilent() async throws {
        #expect(try await hints("#let f(a, b) = a\n#let a = 1\n#f(a, 2)\n") == ["b:@2"])
    }

    @Test func singlePositionalParameterIsSilent() async throws {
        // `1` fills the one positional parameter (a sink does not count), `2` goes into the sink.
        #expect(try await hints("#let one(x, ..rest) = x\n#one(1, 2)\n") == [])
    }

    @Test func editsInAnotherFileDuringARunAreMapped() async throws {
        let a = "#let f(p, q) = p\n#f(1, 2)\n#include \"b.typ\"\n", bText = "#calc.pow(2, 3)\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": a, "b.typ": bText])
        let main = try await p.open(Self.main), b = try await p.open(RelPath("b.typ")!)
        _ = await p.settle()
        p.inlayHintsEnabled = true
        let run = Task { await p.runInlayHints() }
        await Task.yield()
        type(main, "// x\n", at: 0)
        type(b, "// y\n", at: 0)
        await run.value
        func args(_ buf: Buffer) -> [String] {
            let ns = buf.storage.string as NSString
            return p.inlayHints(in: buf.path).sorted { $0.offset < $1.offset }.map { $0.label + ns.substring(with: NSRange(location: $0.offset, length: 1)) }
        }
        // The query in flight when the edit landed may come back empty; every hint that exists sits on its argument.
        #expect(Set(args(main)).isSubset(of: ["p:1", "q:2"]) && args(main).contains("q:2"))
        #expect(args(b) == ["base:2", "exponent:3"])
    }

    @Test func unknownSignatureIsSilent() async throws {
        #expect(try await hints("#let f = none\n#nope(1, 2)\n") == [])
    }

    @Test func offWhileDisabledAndFollowsEdits() async throws {
        let text = "#let f(a, b) = a\n#f(1, 2)\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": text])
        let b = try await p.open(Self.main)
        _ = await p.settle()
        await p.runInlayHints()
        #expect(p.inlayHints(in: Self.main).isEmpty)               // off by default: nothing computed
        p.inlayHintsEnabled = true
        await p.runInlayHints()
        let one = (text as NSString).range(of: "(1").location + 1
        type(b, "xx", at: 0)
        #expect(p.inlayHints(in: Self.main).map(\.offset).sorted() == [one + 2, one + 5])
        replace(b, NSRange(location: one + 2 + 1, length: 2), with: ",")     // the character before `2` changed
        #expect(p.inlayHints(in: Self.main).map(\.offset) == [one + 2])
        p.inlayHintsEnabled = false
        #expect(p.inlayHints(in: Self.main).isEmpty)
    }
}

@Suite(.serialized) @MainActor struct InlayKernTests {
    private func kerns(_ b: Buffer) -> [Int: CGFloat] {
        var out: [Int: CGFloat] = [:]
        b.storage.enumerateAttribute(.kern, in: NSRange(location: 0, length: b.storage.length)) { v, r, _ in
            if let k = v as? NSNumber { for i in r.location..<NSMaxRange(r) { out[i] = CGFloat(k.doubleValue) } }
        }
        return out
    }

    @Test func hintsAndSwatchesShareTheKerns() async throws {
        let src = "#let f(a, b) = a\n#f(1, 2)\n#let c = rgb(\"#ff8800\")\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": src])
        let b = try await p.open(RelPath("main.typ")!)
        _ = await p.settle()
        p.inlayHintsEnabled = true
        await p.runInlayHints()
        let ns = src as NSString
        let open = ns.range(of: "#f(").location + 2, comma = ns.range(of: "1,").location + 2
        let close = ns.range(of: "\")").location + 1
        #expect(kerns(b) == [open: InlayHints.gap("a:"), comma: InlayHints.gap("b:"), close: Buffer.swatchGap])
        #expect(InlayHints.gap("a:") > 2 * (InlayHints.margin + InlayHints.padding))

        p.inlayHintsEnabled = false            // only the hint gaps go
        #expect(kerns(b) == [close: Buffer.swatchGap])
        p.inlayHintsEnabled = true
        await p.runInlayHints()
        #expect(kerns(b).count == 3)

        // A longer parameter name widens its gap in place.
        replace(b, NSRange(location: ns.range(of: "f(a").location + 2, length: 1), with: "alpha")
        replace(b, NSRange(location: ns.range(of: "= a").location + 6, length: 1), with: "alpha")
        _ = await p.settle()
        await p.runInlayHints()
        let shifted = open + 8
        #expect(kerns(b)[shifted] == InlayHints.gap("alpha:"))
        #expect(InlayHints.gap("alpha:") > InlayHints.gap("a:"))
        #expect(kerns(b).count == 3)
    }
}
