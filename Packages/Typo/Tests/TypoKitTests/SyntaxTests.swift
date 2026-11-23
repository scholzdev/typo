import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

@Suite(.serialized) @MainActor struct SyntaxTests {
    static let fixture = """
    = Heading here
    Some *strong* and _emph_ text. // note
    #let x = 42
    #text("str", red)[hi] <lab> and @lab with `code` and \\# done.
    Inline $x^2 + y$ math.
    """

    static func whole(_ s: NSTextStorage) -> NSRange { NSRange(location: 0, length: s.length) }

    /// Tags covering exactly the first occurrence of `needle` (a span may be a sub-range of it).
    static func tags(_ needle: String, in text: String, spans: [SyntaxSpan]) -> Set<SyntaxTag> {
        let r = (text as NSString).range(of: needle)
        precondition(r.location != NSNotFound, needle)
        return Set(spans.filter { NSIntersectionRange($0.range, r).length > 0 }.map(\.tag))
    }

    // 1
    @Test func tagCoverage() {
        let spans = SyntaxMirror(Self.fixture).spans(in: NSRange(location: 0, length: (Self.fixture as NSString).length))
        let t = { Self.tags($0, in: Self.fixture, spans: spans) }
        #expect(t("Heading here") == [.heading])
        #expect(t("*strong*").contains(.strong))
        #expect(t("_emph_").contains(.emph))
        #expect(t("// note") == [.comment])
        #expect(t("\"str\"") == [.string])
        #expect(t("42") == [.number])
        #expect(t("#text").contains(.function))
        #expect(t("let").contains(.keyword))
        #expect(t("<lab>") == [.label])
        #expect(t("@lab") == [.ref])
        #expect(t("`code`") == [.raw])
        #expect(t("\\#") == [.escape])
        #expect(t("$x^2 + y$").contains(.mathDelimiter))
        #expect(t("^").contains(.mathOperator))
    }

    // 2, 3, 4 share one edit sequence; every step is checked, not only the end.
    static let sequenceText = "= Title ä\n\nA paragraph with words, and more words here. Then *bold* text.\nSecond line here.\n\n#let x = 1.5em + 2cm\n"

    func runSequence(_ b: Buffer, check: () -> Void) {
        let um = b.undoManager
        um.groupsByEvent = false
        let ns = { b.storage.string as NSString }
        func at(_ s: String) -> Int { ns().range(of: s).location }
        check()
        type(b, "$", at: at("and more")); check()                       // lone $ mid paragraph
        type(b, "x", at: at("and more")); check()
        replace(b, NSRange(location: at("$"), length: 1), with: ""); check()   // and delete it again
        type(b, "😀é", at: at("Second")); check()                          // emoji, two-unit scalar
        replace(b, ns().range(of: "😀é"), with: ""); check()
        let start = at("here. Then"), end = at("Second line") + 6
        replace(b, NSRange(location: start, length: end - start), with: ""); check()   // deletion across lines
        um.undo(); check()
        um.undo(); check()
        um.redo(); check()
        type(b, "*", at: at("Title")); check()                             // unbalanced strong
        type(b, "#", at: 0); check()
        type(b, "\"", at: at("let") + 4); check()                          // unterminated string
        um.beginUndoGrouping()
        b.storage.beginEditing()                                           // grouped edit, one union range
        replace(b, NSRange(location: 0, length: 0), with: "_")
        replace(b, NSRange(location: b.storage.length, length: 0), with: "\n== Tail `r")
        b.storage.endEditing()
        um.endUndoGrouping(); check()
        replace(b, NSRange(location: 0, length: b.storage.length), with: Self.sequenceText + "$ a + b $\n"); check()
        var caret = b.storage.length
        for ch in "// TODO x" { type(b, String(ch), at: caret); caret += 1; check() }   // marker appears letter by letter
        replace(b, NSRange(location: at("TODO") + 2, length: 0), with: " "); check()  // split it
        replace(b, NSRange(location: at("TO D"), length: 4), with: "FIXME"); check()
        replace(b, NSRange(location: at("// FIXME"), length: 2), with: ""); check()    // no longer a comment
    }

    static func colorRuns(_ s: NSTextStorage) -> [String] {
        var out: [String] = []
        s.enumerateAttribute(.foregroundColor, in: whole(s)) { v, r, _ in out.append("\(r.location),\(r.length),\(String(describing: v))") }
        return out
    }

    @Test func incrementalEqualsFromScratchAndStorageEqualsFullHighlight() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": Self.sequenceText])
        let b = try await p.open(RelPath("main.typ")!)
        var steps = 0
        runSequence(b) {
            steps += 1
            let fresh = SyntaxMirror(b.storage.string)
            #expect(b.syntax.spans(in: Self.whole(b.storage)) == fresh.spans(in: Self.whole(b.storage)), "step \(steps)")   // 2
            let reference = NSTextStorage(string: b.storage.string)                                                          // 3
            Highlighter.recolor(reference, fresh, Self.whole(reference))
            #expect(Self.colorRuns(b.storage) == Self.colorRuns(reference), "step \(steps)")
            #expect(b.syntax.prose(in: Self.whole(b.storage)) == fresh.prose(in: Self.whole(b.storage)), "step \(steps)")
        }
        _ = await p.settle()
        #expect(p.resyncCount == 0)                                                                                          // 4
        #expect(await p.engine.overlayText(b.path) == b.storage.string)
    }

    // 5
    @Test func proseRanges() async throws {
        let text = "= Heading words\n\nParagraph words don't count math.\n\n$ alpha beta $\n\n#let x = \"stringword\"\n\n`rawword`\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": text])
        let b = try await p.open(RelPath("main.typ")!)
        let ns = b.storage.string as NSString
        let ranges = b.proseRanges(in: Self.whole(b.storage))
        func isProse(_ w: String) -> Bool {
            let r = ns.range(of: w)
            return ranges.contains { NSIntersectionRange($0, r) == r }
        }
        for w in ["Heading", "words", "Paragraph", "don't", "count"] { #expect(isProse(w), "\(w)") }
        for w in ["alpha", "beta", "stringword", "rawword", "let"] { #expect(!isProse(w), "\(w)") }
    }

    @Test func proseExcludesImports() async throws {
        let text = "#import \"@preview/cetz:0.3.4\": canvas, draw\n#import \"utilz.typ\": helpr as hlp\n#include \"kapitl.typ\"\n\nReal words here.\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": text])
        let b = try await p.open(RelPath("main.typ")!)
        let ns = b.storage.string as NSString
        let ranges = b.proseRanges(in: Self.whole(b.storage))
        for w in ["preview", "cetz", "canvas", "draw", "utilz", "helpr", "hlp", "kapitl", "import", "include"] {
            let r = ns.range(of: w)
            #expect(!ranges.contains { NSIntersectionRange($0, r).length > 0 }, "\(w)")
        }
        #expect(ranges.contains { NSIntersectionRange($0, ns.range(of: "Real")).length > 0 })
    }

    @Test(arguments: [
        "#{ import \"utilz.typ\": helpr }",
        "#import \"utilz.typ\"",
        "#import \"utilz.typ\": (\n  helpr,\n  zzzq,\n)",
        "#[#import \"utilz.typ\": helpr]",
        "#show: helpr.with(zzzq: 1)",
        "#import \"utilz.typ\": *",
        "#import \"@prev",
        "#import \"utilz.typ\": helpr, zzzq",
        "#import \"utilz.typ\": helpr as zzzq",
    ])
    func proseExcludesImportVariants(_ line: String) async throws {
        let text = "Real words here.\n\n" + line + "\n\nMore words.\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": text])
        let b = try await p.open(RelPath("main.typ")!)
        let ns = b.storage.string as NSString
        let start = ns.range(of: line).location
        let ranges = b.proseRanges(in: Self.whole(b.storage))
        for r in ranges { #expect(NSIntersectionRange(r, NSRange(location: start, length: line.utf16.count)).length == 0, "\(ns.substring(with: r)) in \(line)") }
        // Marks on the line are cleared through the gaps between prose pieces.
        let gaps = b.nonProseRanges(in: Self.whole(b.storage))
        #expect(gaps.contains { NSLocationInRange(start, $0) && NSMaxRange($0) >= start + line.utf16.count })
    }

    @Test func proseExcludesMathWords() async throws {
        let text = "Intro words\n\n$ integral_0^1 x^2 dif x = 1/3 $\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": text])
        let b = try await p.open(RelPath("main.typ")!)
        let r = (b.storage.string as NSString).range(of: "dif")
        let ranges = b.proseRanges(in: Self.whole(b.storage))
        #expect(!ranges.contains { NSIntersectionRange($0, r).length > 0 })
    }

    // 6: reported, not asserted
    @Test func keystrokeCost() async throws {
        let (p, _) = try await TestEnv.project("sample")
        let b = try await p.open(RelPath("main.typ")!)
        var at = b.storage.length / 2
        var times: [Duration] = []
        let clock = ContinuousClock()
        for _ in 0..<200 {
            times.append(clock.measure { b.storage.replaceCharacters(in: NSRange(location: at, length: 0), with: "x") })
            at += 1
        }
        times.sort()
        let us = Double(times[times.count / 2].components.attoseconds) / 1e12
        #if DEBUG
        let profile = "debug"
        #else
        let profile = "release"
        #endif
        print("[timing] syntax delegate pass, \(b.storage.length) chars, median of 200 inserts: \(us) us (\(profile))")
        #expect(b.syntax.spans(in: Self.whole(b.storage)) == SyntaxMirror(b.storage.string).spans(in: Self.whole(b.storage)))
    }
}
