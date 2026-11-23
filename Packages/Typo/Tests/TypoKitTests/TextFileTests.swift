import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite struct TextFileTests {
    let s = TextFileSettings()

    @Test func decodesUTF8WithAndWithoutBOM() {
        let plain = TextFile.decode(Data("héllo".utf8), settings: s)!
        #expect(plain.text == "héllo" && !plain.format.bom)
        let bom = TextFile.decode(Data([0xEF, 0xBB, 0xBF] + Array("héllo".utf8)), settings: s)!
        #expect(bom.text == "héllo" && bom.format.bom)
        #expect(TextFile.encode(bom.text, format: bom.format, settings: s).data == Data([0xEF, 0xBB, 0xBF] + Array("héllo".utf8)))
    }

    @Test func latin1Fallback() {
        let latin = Data([0x63, 0x61, 0x66, 0xE9])
        #expect(TextFile.decode(latin, settings: s) == nil)
        let st = TextFileSettings(fallback: .latin1)
        let r = TextFile.decode(latin, settings: st)!
        #expect(r.text == "café" && r.format.encoding == .latin1)
        #expect(TextFile.encode(r.text, format: r.format, settings: st).data == latin)
    }

    @Test func unencodableTextIsWrittenAsUTF8() {
        let f = FileFormat(encoding: .latin1)
        let out = TextFile.encode("a😀", format: f, settings: s)
        #expect(out.data == Data("a😀".utf8) && out.format.encoding == .utf8)
    }

    @Test func detectsLineEndings() {
        #expect(TextFile.detectLineEnding("a\nb\n") == .lf)
        #expect(TextFile.detectLineEnding("a\r\nb\r\n") == .crlf)
        #expect(TextFile.detectLineEnding("a\rb\r") == .cr)
        #expect(TextFile.detectLineEnding("abc") == nil)
        #expect(TextFile.detectLineEnding("a\r\nb\r\nc\n") == .crlf)      // mixed: the most frequent wins
        #expect(TextFile.detectLineEnding("a\r\nb\nc\n") == .lf)
        #expect(TextFile.detectLineEnding("a\r\nb\n") == .lf)            // a tie goes to LF
    }

    @Test func normalizeAndApplyRoundTrip() {
        #expect(TextFile.normalize("a\r\nb\rc\nd") == "a\nb\nc\nd")
        #expect(TextFile.apply(.crlf, to: "a\nb\n") == "a\r\nb\r\n")
        #expect(TextFile.apply(.cr, to: "a\nb") == "a\rb")
        for e in LineEnding.allCases { #expect(TextFile.normalize(TextFile.apply(e, to: "x\n\ny\n")) == "x\n\ny\n") }
    }

    @Test func crlfFileRoundTripsByteIdentical() {
        let bytes = Data("a\r\nb\r\n\r\nc".utf8)
        let r = TextFile.decode(bytes, settings: s)!
        #expect(r.text == "a\nb\n\nc" && r.format.lineEnding == .crlf)
        #expect(TextFile.encode(r.text, format: r.format, settings: s).data == bytes)
    }

    @Test func convertingWritesUTF8WithDefaultEnding() {
        let st = TextFileSettings(fallback: .latin1, lineEnding: .lf, convertOnSave: true)
        let r = TextFile.decode(Data([0x63, 0xE9, 0x0D, 0x0A]), settings: st)!
        let out = TextFile.encode(r.text, format: r.format, settings: st)
        #expect(out.data == Data("cé\n".utf8) && out.format == FileFormat())
    }

    @Test func emptyFileTakesTheDefaultEnding() {
        #expect(TextFile.decode(Data(), settings: TextFileSettings(lineEnding: .crlf))!.format.lineEnding == .crlf)
    }

    @Test @MainActor func openedAndSavedCRLFAndLatin1FilesStayIntact() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "x"])
        let crlf = Data("a\r\nb\r\n".utf8), latin = Data([0x63, 0xE9, 0x0A])
        try crlf.write(to: root.appending(path: "c.typ"))
        try latin.write(to: root.appending(path: "l.typ"))
        p.textFileSettings = { TextFileSettings(fallback: .latin1) }
        let c = try await p.open(RelPath("c.typ")!), l = try await p.open(RelPath("l.typ")!)
        #expect(c.storage.string == "a\nb\n" && !c.isDirty && l.storage.string == "cé\n")
        c.apply([Replacement(range: NSRange(location: 0, length: 1), text: "z")])
        l.apply([Replacement(range: NSRange(location: 0, length: 1), text: "d")])
        try await p.saveAll()
        #expect(try Data(contentsOf: root.appending(path: "c.typ")) == Data("z\r\nb\r\n".utf8))
        #expect(try Data(contentsOf: root.appending(path: "l.typ")) == Data([0x64, 0xE9, 0x0A]))
        await p.reloadChangedFiles()
        #expect(!c.isDirty && !p.changedOnDisk.contains(c.path))
    }
}

@Suite struct WhitespaceTrimTests {
    func trim(_ text: String, blank: Bool, typst: Bool = true) -> String {
        let ns = text as NSString
        var out = text
        let toks = typst ? TypstSyntax.tokens(in: text) : []
        for e in WhitespaceTrim.edits(in: text, tokens: toks, blankLines: blank).reversed() { out = (out as NSString).replacingCharacters(in: e.range, with: e.text) }
        _ = ns
        return out
    }

    @Test func trimsContentLinesOnly() {
        #expect(trim("a  \n   \nb\t \n", blank: false) == "a\n   \nb\n")
    }

    @Test func blankLinesToo() {
        #expect(trim("a  \n   \n\t\nb", blank: true) == "a\n\n\nb")
        #expect(trim("a \t", blank: true) == "a")                         // last line without newline
    }

    @Test func rawBlocksAndStringsKeepTheirLineEnds() {
        let raw = "x  \n```\ncode  \n  \nmore\n```  \ny  "
        #expect(trim(raw, blank: true) == "x\n```\ncode  \n  \nmore\n```\ny")
        let str = "#let s = \"a  \nb\"  \nz  "
        #expect(trim(str, blank: true) == "#let s = \"a  \nb\"\nz")
    }

    @Test func plainTextHasNoProtection() {
        #expect(trim("```\ncode  \n```", blank: true, typst: false) == "```\ncode\n```")
    }
}

@Suite struct TrimOnSaveTests {
    @Test @MainActor func dirtyBuffersAreTrimmedAsOneUndoStep() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "a  \nb"])
        let b = try await p.open(RelPath("main.typ")!)
        b.apply([Replacement(range: NSRange(location: 4, length: 1), text: "c  ")])
        b.undoManager.removeAllActions()
        p.prepareDirtyBuffersForSave(format: nil, trimBlankLines: false)
        #expect(b.storage.string == "a\nc")
        b.undoManager.undo()
        #expect(b.storage.string == "a  \nc  ")
    }
}
