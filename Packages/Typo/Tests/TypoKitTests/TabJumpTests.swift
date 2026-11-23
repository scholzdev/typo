import Testing
import Foundation
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@MainActor
struct TabJumpTests {
    /// Marks: `|` is the caret. Returns the selection a Tab (or Shift-Tab) makes, as text with `|` / `[..]` markers.
    static func jump(_ marked: String, forward: Bool = true) async throws -> String? {
        let text = marked.replacingOccurrences(of: "|", with: "")
        let caret = (marked as NSString).range(of: "|").location
        let (p, _) = try await TestEnv.project(files: ["main.typ": text])
        let b = try await p.open(RelPath("main.typ")!)
        guard let r = b.tabJump(from: NSRange(location: caret, length: 0), forward: forward) else { return nil }
        let ns = text as NSString
        return r.length == 0 ? ns.replacingCharacters(in: r, with: "|") : ns.replacingCharacters(in: r, with: "<" + ns.substring(with: r) + ">")
    }

    @Test func tableCellsForwardAndBack() async throws {
        let t = "#table(columns: 3, [a], [], [c])"
        #expect(try await Self.jump("#table(|columns: 3, [a], [], [c])") == "#table(columns: <3>, [a], [], [c])")
        #expect(try await Self.jump("#table(columns: <3>, [a], [], [c])".replacingOccurrences(of: "<3>", with: "|3")) == "#table(columns: 3, [<a>], [], [c])")
        #expect(try await Self.jump("#table(columns: 3, [|a], [], [c])") == "#table(columns: 3, [a], [|], [c])")
        #expect(try await Self.jump("#table(columns: 3, [a], [|], [c])") == "#table(columns: 3, [a], [], [<c>])")
        #expect(try await Self.jump("#table(columns: 3, [a], [], [|c])", forward: false) == "#table(columns: 3, [a], [|], [c])")
        #expect(try await Self.jump("#table(columns: 3, [a], [|], [c])", forward: false) == "#table(columns: 3, [<a>], [], [c])")
        #expect(try await Self.jump("#table(columns: 3, [|a], [], [c])", forward: false) == "#table(columns: <3>, [a], [], [c])")
        _ = t
    }

    @Test func figureImageToCaption() async throws {
        #expect(try await Self.jump("#figure(image(\"x|.png\"), caption: [])") == "#figure(image(\"x.png\"), caption: [|])")
    }

    @Test func nestedAndEnds() async throws {
        #expect(try await Self.jump("#table(columns: 2, [#emph[x|]], [b])") == "#table(columns: 2, [#emph[x]], [<b>])")
        #expect(try await Self.jump("#table(columns: 2, [a], [b|])") == "#table(columns: 2, [a], [b])|")
        #expect(try await Self.jump("#table(columns: 2, [#emph[x]|], [b])", forward: false) == "#table(columns: <2>, [#emph[x]], [b])")
        #expect(try await Self.jump("#f(|a, b)", forward: false) == nil)
        #expect(try await Self.jump("#f(a, b)[c|]") == "#f(a, b)[c]|")
    }

    @Test func normalTabCases() async throws {
        #expect(try await Self.jump("#block[- a|]") == nil)
        #expect(try await Self.jump("#ta|ble(columns: 2, [a], [b])") == nil)
        #expect(try await Self.jump("- #f(a|, b)") == nil)
        #expect(try await Self.jump("plain| text") == nil)
    }

    @Test func indentationKeepsNormalTab() async throws {
        #expect(try await Self.jump("#block[\n  text\n|]") == nil)
        #expect(try await Self.jump("#block[\n  text\n  |]") == nil)
        #expect(try await Self.jump("#table(columns: 2,\n  |[a], [b])") == nil)
        #expect(try await Self.jump("#table(columns: 2,\n  [a|], [b])") == "#table(columns: 2,\n  [a], [<b>])")
    }

    @Test func shiftTabOutdentsIndentation() async throws {
        func run(_ marked: String) async throws -> String? {
            let text = marked.replacingOccurrences(of: "|", with: "")
            let caret = (marked as NSString).range(of: "|").location
            let (p, _) = try await TestEnv.project(files: ["main.typ": text])
            let b = try await p.open(RelPath("main.typ")!)
            guard let r = b.outdentAtCaret(NSRange(location: caret, length: 0)) else { return nil }
            return (b.storage.string as NSString).replacingCharacters(in: r, with: "|")
        }
        #expect(try await run("a\n\t|\t]") == "a\n|\t]")
        #expect(try await run("a\n\t\t|]") == "a\n\t|]")
        #expect(try await run("a\n      |]") == "a\n    |]")
        #expect(try await run("a\n  |]") == "a\n|]")
        #expect(try await run("a\n|]") == nil)
        #expect(try await run("a\n  b|]") == nil)
        #expect(try await Self.jump("#table(columns: 2, [a], [b|])", forward: false) == "#table(columns: 2, [<a>], [b])")
    }

    @Test func unfinishedStringsAndComments() async throws {
        #expect(try await Self.jump("#table(columns: 2, [a|],") == "#table(columns: 2, [a],|")
        #expect(try await Self.jump("#f(\"a, b\"|, /* c, d */ [e])") == "#f(\"a, b\", /* c, d */ [<e>])")
        #expect(try await Self.jump("#f(a, // x, y\n  b|)") == "#f(a, // x, y\n  b)|")
    }

    @Test func snippetPlaceholdersReachLaterArguments() async throws {
        let s = Snippet.parse("figure(${}, caption: ${})")
        let text = "#" + s.text
        let (p, _) = try await TestEnv.project(files: ["main.typ": text])
        let b = try await p.open(RelPath("main.typ")!)
        let first = s.selection(insertedAt: 1)
        let next = b.tabJump(from: first, forward: true)
        #expect(next == NSRange(location: (text as NSString).length - 1, length: 0))
    }
}
