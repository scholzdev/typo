import Foundation
import ImageIO
import PDFKit
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite(.serialized) @MainActor struct ExportTests {
    private static let twoPages = ["main.typ": "#set page(width: 200pt, height: 100pt)\nFirst page.\n#pagebreak()\nSecond page.\n"]

    private func ascii(_ d: Data) -> String { String(decoding: d, as: UTF8.self) }

    @Test func pdfAMarksTheArchiveStandardAndPlainDoesNot() async throws {
        let (p, _) = try await TestEnv.project(files: Self.twoPages)
        let plain = ascii(try await p.exportPDF())
        let a2 = ascii(try await p.exportPDF(standard: .pdfA2b))
        let a3 = ascii(try await p.exportPDF(standard: .pdfA3b))
        #expect(!plain.contains("pdfaid"))
        #expect(a2.contains("pdfaid:part>2") && a2.contains("pdfaid:conformance>B"))
        #expect(a3.contains("pdfaid:part>3") && a3.contains("pdfaid:conformance>B"))
    }

    @Test func pdfUA1NeedsATitleAndAltText() async throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><rect width=\"10\" height=\"10\"/></svg>"
        let (p, _) = try await TestEnv.project(files: ["main.typ": "Hello\n", "a.svg": svg])
        do {
            _ = try await p.exportPDF(standard: .ua1)
            Issue.record("UA-1 export without a title succeeded")
        } catch {
            #expect("\(error)".lowercased().contains("title"))
        }
        let (ok, _) = try await TestEnv.project(files: ["main.typ": "#set document(title: \"T\")\nHello #image(\"a.svg\", alt: \"A square\")\n", "a.svg": svg])
        let ua = ascii(try await ok.exportPDF(standard: .ua1))
        #expect(ua.contains("pdfuaid:part>1"))
    }

    @Test func pngPagesHavePointsTimesPpiPixels() async throws {
        let (p, _) = try await TestEnv.project(files: Self.twoPages)
        let pages = try await p.exportPages(.png(ppi: 144))
        #expect(pages.count == 2)
        for d in pages {
            #expect(Array(d.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            let src = try #require(CGImageSourceCreateWithData(d as CFData, nil))
            let props = try #require(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
            #expect(abs((props[kCGImagePropertyPixelWidth] as! Int) - 400) <= 1)   // 200 pt * 144 / 72
            #expect(abs((props[kCGImagePropertyPixelHeight] as! Int) - 200) <= 1)
            #expect(abs((props[kCGImagePropertyDPIWidth] as! Double) - 144) < 0.5)
        }
    }

    @Test func svgPagesAreSvgDocuments() async throws {
        let (p, _) = try await TestEnv.project(files: Self.twoPages)
        let pages = try await p.exportPages(.svg)
        #expect(pages.count == 2)
        for d in pages {
            let s = ascii(d)
            #expect(s.hasPrefix("<svg") || s.hasPrefix("<?xml"))
            #expect(s.contains("</svg>"))
        }
    }

    @Test func exportOfADocumentWithErrorsReportsDiagnostics() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "#panic(\"boom\")"])
        await #expect(throws: ProjectError.self) { try await p.exportPages(.svg) }
    }

    // MARK: Section words

    private func sections(_ p: Project) async -> ([SectionWords], Int) {
        _ = await p.settle()
        await p.wordsTask?.value
        return (p.sectionWords, p.wordCount)
    }

    @Test func sectionWordsFollowHeadingsThroughIncludesAndSumToTheTotal() async throws {
        let (p, _) = try await TestEnv.project(files: [
            "main.typ": "Front matter words.\n= One\nAlpha beta.\n#include \"two.typ\"\n== Sub\nGamma delta epsilon.\n",
            "two.typ": "= Two\nZeta eta theta iota.\n",
        ])
        let (s, total) = await sections(p)
        #expect(s.map(\.title) == ["", "One", "Two", "Sub"])
        #expect(s.map(\.level) == [0, 1, 1, 2])
        #expect(s.map(\.words) == [3, 3, 5, 4])           // heading words included, no page numbers here
        #expect(s.map(\.words).reduce(0, +) == total)
    }

    @Test func sectionSumMatchesTheTotalWithPageNumbersAcrossPages() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ":
            "#set page(numbering: \"1\")\n= A\nOne two.\n#pagebreak()\n= B\nThree four five.\n#pagebreak()\n= C\nSix.\n"])
        let (s, total) = await sections(p)
        #expect(s.count == 4 && s[0].words == 0)
        #expect(s.map(\.words).reduce(0, +) == total)
        #expect(s.map(\.page) == [0, 0, 1, 2])
    }
}

@Suite struct WritingProgressTests {
    private let cal = Calendar(identifier: .gregorian)
    private func date(_ d: Int, _ h: Int = 12) -> Date { cal.date(from: DateComponents(year: 2026, month: 3, day: d, hour: h))! }

    @Test func todayCountsFromTheFirstCountOfTheDay() {
        var p = WritingProgress()
        p.record(total: 1000, on: date(1, 9), calendar: cal)
        p.record(total: 1200, on: date(1, 18), calendar: cal)
        #expect(p.today(total: 1500) == 500)
        #expect(p.today(total: 900) == -100)
    }

    @Test func aNewDayStartsAgainFromTheCurrentCount() {
        var p = WritingProgress()
        p.record(total: 1000, on: date(1), calendar: cal)
        p.record(total: 1800, on: date(2), calendar: cal)
        #expect(p.today(total: 1850) == 50)
    }

    @Test func noGoalNoFractionAndGoalClamps() {
        var p = WritingProgress()
        #expect(p.fraction(total: 500) == nil)
        p.goal = 0
        #expect(p.fraction(total: 500) == nil)
        p.goal = 1000
        #expect(p.fraction(total: 250) == 0.25)
        #expect(p.fraction(total: 5000) == 1)
    }

    @Test func storeRoundTripsPerProject() throws {
        let defaults = try #require(UserDefaults(suiteName: "typstcore-progress-\(UUID().uuidString)"))
        let a = ProgressStore(ProjectID(), defaults: defaults), b = ProgressStore(ProjectID(), defaults: defaults)
        var p = WritingProgress(goal: 20000)
        p.record(total: 70, on: date(1), calendar: cal)
        a.save(p)
        #expect(a.load() == p)
        #expect(b.load() == WritingProgress())
    }
}

@Suite(.serialized) @MainActor struct ArchiveTests {
    @Test func zipHoldsProjectFilesButNoHiddenOnes() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "Hi", "a/b/note.typ": "x", "img/c.txt": "y", ".secret": "s", ".git/config": "g", "a/.hidden": "h"])
        let zip = FileManager.default.temporaryDirectory.appending(path: "archive-\(UUID().uuidString).zip")
        try await p.exportArchive(to: zip)
        try await p.exportArchive(to: zip)   // an existing target is replaced
        let pipe = Pipe(), proc = Process()
        proc.executableURL = URL(filePath: "/usr/bin/unzip"); proc.arguments = ["-Z1", zip.path]; proc.standardOutput = pipe
        try proc.run()
        let names = Set(String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").map(String.init).filter { !$0.hasSuffix("/") })
        #expect(names == ["main.typ", "a/b/note.typ", "img/c.txt"])
    }
}

struct EngineVersionsTests {
    @Test func matchBridgeManifest() throws {
        let manifest = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../bridge/Cargo.toml")
        let text = try String(contentsOf: manifest, encoding: .utf8)
        #expect(text.contains("\ntypst = \"\(EngineVersions.typst)\""))
        #expect(text.contains("\ntypstyle-core = \"\(EngineVersions.typstyle)\""))
    }
}
