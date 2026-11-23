import Testing
import Foundation
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

@Suite struct ScopeGuideTests {
    private func levels(_ text: String, unit: Int = 2) -> [Int] {
        let ns = text as NSString
        var starts: [Int] = [], s = 0
        while s < ns.length { starts.append(s); s = NSMaxRange(ns.lineRange(for: NSRange(location: s, length: 0))) }
        return ScopeGuides.levels(in: ns, lineStarts: starts, unit: unit)
    }

    @Test func spacesTabsAndMixed() {
        #expect(ScopeGuides.starts(of: "    x", unit: 2) == [0, 2])
        #expect(ScopeGuides.starts(of: "   x", unit: 2) == [0])           // a partial level is not a level
        #expect(ScopeGuides.starts(of: "\t\tx", unit: 2) == [0, 1])
        #expect(ScopeGuides.starts(of: "  \tx", unit: 2) == [0, 2])
        #expect(ScopeGuides.starts(of: " \tx", unit: 2) == [0])           // the stray space joins the tab's level
        #expect(ScopeGuides.starts(of: "x  ", unit: 2) == [])
        #expect(ScopeGuides.starts(of: "        x", unit: 4) == [0, 4])
    }

    @Test func blankLinesInheritTheSurroundingLevel() {
        #expect(levels("a\n  b\n\n  c\nd\n") == [0, 1, 1, 1, 0])
        #expect(levels("a\n    b\n   \n  c\n") == [0, 2, 1, 1])     // between levels 2 and 1: the smaller
        #expect(levels("  a\n\n") == [1, 0])                        // nothing below counts as 0
        #expect(levels("\t{\n\t\tb\n\n\t\tc\n\t}\n") == [1, 2, 2, 2, 1])
    }
}

@Suite struct HangingIndentTests {
    @Test func columnsFollowTheLeadingBlanks() {
        #expect(HangingIndent.columns("text", extra: 0, tabWidth: 4) == 0)
        #expect(HangingIndent.columns("text", extra: 3, tabWidth: 4) == 3)
        #expect(HangingIndent.columns("    text", extra: 2, tabWidth: 4) == 6)
        #expect(HangingIndent.columns("\t\ttext", extra: 0, tabWidth: 4) == 8)
        #expect(HangingIndent.columns("  \ttext", extra: 1, tabWidth: 4) == 5)   // the tab advances to the next stop
        #expect(HangingIndent.columns("\t", extra: 0, tabWidth: 3.5) == 3.5)
    }
}

@MainActor @Suite struct WrapIndentSyncTests {
    private func heads(_ b: Buffer) -> [CGFloat] {
        let text = b.storage.string as NSString
        var out: [CGFloat] = [], s = 0
        while s < text.length {
            let line = text.lineRange(for: NSRange(location: s, length: 0))
            var eff = NSRange()
            let style = b.storage.attribute(.paragraphStyle, at: line.location, longestEffectiveRange: &eff, in: line) as? NSParagraphStyle
            out.append(eff == line ? style?.headIndent ?? 0 : -1)      // -1: the paragraph is not uniformly styled
            s = NSMaxRange(line)
        }
        return out
    }

    @Test func idempotentAndSurvivesEditsAndRecolor() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= Title\n#let f(x) = {\n  x\n}\n"])
        let b = try await p.open(RelPath("main.typ")!)
        let char = ("0" as NSString).size(withAttributes: [.font: Highlighter.baseFont]).width
        #expect(heads(b) == [0, 0, 2 * char, 0])               // N = 0: only the indented line changes
        #expect(b.storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) == nil)

        b.wrapIndent = 2
        #expect(heads(b) == [2 * char, 2 * char, 4 * char, 2 * char])

        b.storage.beginEditing()
        b.syncWrapIndent()
        #expect(b.storage.editedMask.isEmpty)                   // nothing to do: no attribute write
        b.storage.endEditing()

        type(b, "  more", at: (b.storage.string as NSString).range(of: "  x").location + 3)
        #expect(heads(b) == [2 * char, 2 * char, 4 * char, 2 * char])
        replace(b, NSRange(location: 0, length: 0), with: "    ")
        #expect(heads(b)[0] == 6 * char)
        b.restyle()
        #expect(heads(b) == [6 * char, 2 * char, 4 * char, 2 * char])

        b.wrapIndent = 0
        #expect(heads(b) == [4 * char, 0, 2 * char, 0])
    }
}

@Suite struct OccurrenceTests {
    private let file = RelPath("main.typ")!

    private func marked(_ text: String, at needle: String, offset: Int = 1) -> [String] {
        let ns = text as NSString
        let at = ns.range(of: needle).location + offset
        return Occurrences.ranges(in: text, file: file, at: at).map { "\($0.location):" + ns.substring(with: $0) }
    }

    @Test func otherSitesOfABinding() {
        let text = "#let width = 3\n#let f(x) = x + width\nThe width is #width.\n"
        let ns = text as NSString
        let def = ns.range(of: "width").location
        let use1 = ns.range(of: "+ width").location + 2
        let use2 = ns.range(of: "#width").location + 1
        #expect(marked(text, at: "width") == ["\(use1):width", "\(use2):width"])
        #expect(marked(text, at: "#width", offset: 2) == ["\(def):width", "\(use1):width"])
        #expect(marked(text, at: "(x)") == ["\(ns.range(of: "= x").location + 2):x"])
    }

    @Test func otherSitesOfALabel() {
        let text = "= Intro <intro>\nSee @intro and @intro.\n"
        let ns = text as NSString
        let refs = [ns.range(of: "@intro").location, ns.range(of: "and @intro").location + 4]
        #expect(marked(text, at: "<intro>") == refs.map { "\($0):@intro" })
        #expect(marked(text, at: "and @intro", offset: 5) == ["\(ns.range(of: "<intro>").location):<intro>", "\(refs[0]):@intro"])
    }

    @Test func nothingForProse() {
        let text = "#let width = 3\nThe width is fine, width.\n"
        #expect(marked(text, at: "The width", offset: 5).isEmpty)
        #expect(marked(text, at: "fine").isEmpty)
    }
}
