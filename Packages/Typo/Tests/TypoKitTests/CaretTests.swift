import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine
#if canImport(AppKit)
import AppKit

/// Real Buffer behind a real TextKit 2 NSTextView, configured like the app's editor.
@Suite(.serialized) @MainActor struct CaretTests {
    static let text = "= Title\n\nA paragraph with words, and more words here. Then *bold* text.\nSecond line.\n"

    static func view(_ b: Buffer) -> NSTextView {
        let tv = NSTextView(usingTextLayoutManager: true)
        tv.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.textContentStorage?.textStorage = b.storage
        tv.typingAttributes = Highlighter.base
        return tv
    }

    @Test func caretStaysAfterTypedCharacterAndWideReparse() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": Self.text])
        let b = try await p.open(RelPath("main.typ")!)
        let tv = Self.view(b)
        let ns = { b.storage.string as NSString }

        let word = ns().range(of: "words,").location + 2
        tv.setSelectedRange(NSRange(location: word, length: 0))
        tv.insertText("Q", replacementRange: tv.selectedRange())
        #expect(tv.selectedRange() == NSRange(location: word + 1, length: 0))

        let mid = ns().range(of: "and more").location
        tv.setSelectedRange(NSRange(location: mid, length: 0))
        tv.insertText("$", replacementRange: tv.selectedRange())     // the rest of the paragraph becomes math
        #expect(tv.selectedRange() == NSRange(location: mid + 1, length: 0))

        tv.deleteBackward(nil)
        #expect(tv.selectedRange() == NSRange(location: mid, length: 0))
        #expect(b.storage.string == (Self.text as NSString).replacingCharacters(in: NSRange(location: word, length: 0), with: "Q"))
    }

    /// The layout must render the recolored attributes, not a snapshot taken before recoloring.
    @Test func layoutSeesRecoloredAttributes() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": Self.text])
        let b = try await p.open(RelPath("main.typ")!)
        let tv = Self.view(b)
        let tlm = tv.textLayoutManager!
        let mid = (b.storage.string as NSString).range(of: "and more").location
        tv.setSelectedRange(NSRange(location: mid, length: 0))
        tv.insertText("$", replacementRange: tv.selectedRange())
        tlm.ensureLayout(for: tlm.documentRange)
        let laidOut = NSMutableAttributedString()
        tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: [.ensuresLayout]) { f in
            if let para = f.textElement as? NSTextParagraph { laidOut.append(para.attributedString) }
            return true
        }
        var expected: [String] = [], got: [String] = []
        let whole = NSRange(location: 0, length: b.storage.length)
        b.storage.enumerateAttribute(.foregroundColor, in: whole) { v, r, _ in expected.append("\(r)\(String(describing: v))") }
        laidOut.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: laidOut.length)) { v, r, _ in got.append("\(r)\(String(describing: v))") }
        #expect(laidOut.string == b.storage.string)
        #expect(got == expected)
    }
}
#endif

#if canImport(AppKit)
extension CaretTests {
    /// What the editor does for a key: the pair editor first, the text view otherwise.
    static func key(_ s: String, _ tv: NSTextView, _ b: Buffer) {
        if !b.handleTyped(s, replacing: tv.selectedRange(), in: tv) { tv.insertText(s, replacementRange: tv.selectedRange()) }
    }

    @Test func modeAtCaretFromSyntaxMirror() async throws {
        let text = "Hi $x$ #f(1) `r` // c\n#[a]\n#let s = \"q\""
        let (p, _) = try await TestEnv.project(files: ["main.typ": text])
        let b = try await p.open(RelPath("main.typ")!)
        let ns = text as NSString
        func mode(_ needle: String, after: Bool = false) -> SyntaxMode {
            let r = ns.range(of: needle)
            return b.syntax.mode(at: after ? NSMaxRange(r) : r.location + 1)
        }
        #expect(b.syntax.mode(at: 0) == .markup)
        #expect(mode("Hi") == .markup)
        #expect(mode("$x$") == .math)                       // after the opening $
        #expect(mode("$x$", after: true) == .markup)        // after the closing $
        #expect(mode("f(1)") == .code)
        #expect(mode("\"q\"") == .text)
        #expect(mode("`r`") == .text)
        #expect(mode("// c") == .text)
        #expect(b.syntax.mode(at: ns.range(of: "#[").location + 2) == .markup)   // inside a content block
    }

    @Test func includeQuoteClosesThenCompletesAndAccepts() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "", "kapitel.typ": "= K\n"])
        let b = try await p.open(RelPath("main.typ")!)
        let tv = Self.view(b)
        for ch in "#include \"" { Self.key(String(ch), tv, b) }
        #expect(b.storage.string == "#include \"\"")
        #expect(tv.selectedRange() == NSRange(location: 10, length: 0))
        let list = try #require(await p.complete(in: b.path, at: 10, explicit: false))
        let live = try #require(p.live(list, caret: 10))
        let item = try #require(live.items.first { $0.label.contains("kapitel.typ") })
        tv.insertText(Snippet.parse(item.apply ?? item.label).text, replacementRange: live.range)
        #expect(b.storage.string == "#include \"kapitel.typ\"")
    }

    @Test func editorFlowStepOverBackspaceAndUndo() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "x "])
        let b = try await p.open(RelPath("main.typ")!)
        let tv = Self.view(b)
        tv.setSelectedRange(NSRange(location: 2, length: 0))
        Self.key("(", tv, b)
        #expect(b.storage.string == "x ()")
        Self.key("a", tv, b)
        Self.key(")", tv, b)                                       // steps over the auto closer
        #expect(b.storage.string == "x (a)" && tv.selectedRange().location == 5)
        Self.key("(", tv, b)
        #expect(b.storage.string == "x (a)()")
        #expect(b.handleBackspace(in: tv))                         // empty auto pair: both go
        #expect(b.storage.string == "x (a)" && tv.selectedRange().location == 5)
        tv.setSelectedRange(NSRange(location: 3, length: 0))
        #expect(!b.handleBackspace(in: tv))                        // `(` before `a` is not an empty pair
        _ = await p.settle()
        #expect(await p.engine.overlayText(b.path) == b.storage.string)
    }

    @Test func findReplaceAllIsOneUndoStepAndEngineStaysExact() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "one two one two one\n"])
        let b = try await p.open(RelPath("main.typ")!)
        let um = b.undoManager
        um.groupsByEvent = false
        let before = b.storage.string
        um.beginUndoGrouping()
        b.storage.beginEditing()
        for r in (b.storage.string as NSString).ranges(of: "one").reversed() { replace(b, r, with: "1") }
        b.storage.endEditing()
        um.endUndoGrouping()
        #expect(b.storage.string == "1 two 1 two 1\n")
        _ = await p.settle()
        #expect(await p.engine.overlayText(b.path) == b.storage.string)
        um.undo()
        #expect(b.storage.string == before)
        #expect(!um.canUndo)
        _ = await p.settle()
        #expect(await p.engine.overlayText(b.path) == before)
        #expect(p.resyncCount == 0)
    }
}

private extension NSString {
    func ranges(of s: String) -> [NSRange] {
        var out: [NSRange] = [], from = 0
        while true {
            let r = range(of: s, range: NSRange(location: from, length: length - from))
            if r.location == NSNotFound { return out }
            out.append(r); from = NSMaxRange(r)
        }
    }
}
#endif
