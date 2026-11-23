import Foundation
import PDFKit
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@MainActor struct FontNamesTests {
    @Test func engineListsItsFontFamilies() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "x"])
        let names = await p.fontFamilyNames(host: RelPath("main.typ")!)
        #expect(names.contains("Libertinus Serif") && names.contains("DejaVu Sans Mono"))
        #expect(!names.contains { $0.contains("\"") })
    }

    /// Geist (OFL, Fixtures/fonts) is not installed, so only the project copy can provide it.
    @Test func projectFontFileIsUsableUntilDeleted() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "#set text(font: \"Geist\")\nHello"])
        let host = RelPath("main.typ")!
        /// Whether the compile warns about the family, and whether the engine lists it.
        func state() async throws -> (warns: Bool, listed: Bool) {
            let r = try #require(await p.settle())
            return (r.snapshot.diagnostics.contains { $0.message.contains("unknown font family") }, await p.fontFamilyNames(host: host).contains("Geist"))
        }
        var s = try await state()
        #expect(s.warns && !s.listed)

        let font = root.appending(path: "fonts/Geist-Regular.ttf")
        try FileManager.default.createDirectory(at: font.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: TestEnv.fixtures.appending(path: "fonts/Geist-Regular.ttf"), to: font)
        await p.refreshFiles()
        s = try await state()
        #expect(!s.warns && s.listed)
        let fonts = baseFonts(try await p.exportPDF())
        #expect(fonts.contains { $0.contains("Geist") }, "\(fonts)")

        try FileManager.default.removeItem(at: font)
        await p.refreshFiles()
        s = try await state()
        #expect(s.warns && !s.listed)
    }

    /// Every /BaseFont on the PDF's pages (the dictionaries may sit in compressed object streams, so no byte search).
    private func baseFonts(_ pdf: Data) -> [String] {
        guard let doc = PDFDocument(data: pdf) else { return [] }
        var out: [String] = []
        for i in 0..<doc.pageCount {
            guard let dict = doc.page(at: i)?.pageRef?.dictionary else { continue }
            var res: CGPDFDictionaryRef?, fonts: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(dict, "Resources", &res), let res,
                  CGPDFDictionaryGetDictionary(res, "Font", &fonts), let fonts else { continue }
            CGPDFDictionaryApplyBlock(fonts, { _, obj, _ in
                var f: CGPDFDictionaryRef?, name: UnsafePointer<CChar>?
                if CGPDFObjectGetValue(obj, .dictionary, &f), let f, CGPDFDictionaryGetName(f, "BaseFont", &name), let name {
                    out.append(String(cString: name))
                }
                return true
            }, nil)
        }
        return out
    }
}
