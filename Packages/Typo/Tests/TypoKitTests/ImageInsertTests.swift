import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite @MainActor struct ImageInsertTests {
    @Test func uniqueNamesCountFromTwo() {
        let taken: Set = ["photo.png", "photo-2.png"]
        #expect(ImageInsert.uniqueName("photo.png") { taken.contains($0) } == "photo-3.png")
        #expect(ImageInsert.uniqueName("other.png") { taken.contains($0) } == "other.png")
    }

    @Test func pastedNameUsesLocalDigits() {
        let date = Date(timeIntervalSince1970: 1_795_000_000)    // 2026-11-18 11:06:40 UTC
        #expect(ImageInsert.pastedName(at: date, timeZone: TimeZone(identifier: "UTC")!) == "screenshot-20261118-110640.png")
        #expect(ImageInsert.pastedName(at: date, timeZone: TimeZone(identifier: "Europe/Berlin")!) == "screenshot-20261118-120640.png")
    }

    @Test func pathsAreRelativeToTheEditedFilesFolder() {
        let r = { ImageInsert.relativePath(from: RelPath($0)!, to: RelPath($1)!) }
        #expect(r("main.typ", "images/x.png") == "images/x.png")
        #expect(r("chapters/a.typ", "images/x.png") == "../images/x.png")
        #expect(r("a/b/c.typ", "a/img/x.png") == "../img/x.png")
        #expect(r("a/c.typ", "a/x.png") == "x.png")
        #expect(r("images/notes.typ", "images/x.png") == "x.png")
        #expect(r("a/b.typ", "x.png") == "../x.png")
    }

    @Test func labelsKeepOnlyLabelCharacters() {
        #expect(ImageInsert.label(for: "Screenshot 2026-11-18 at 10.30.00") == "screenshot-2026-11-18-at-10.30.00")
        #expect(ImageInsert.label(for: "Über  Bild (1)") == "über-bild-1")
        #expect(ImageInsert.label(for: "  ") == "image")
        #expect(ImageInsert.label(for: "a_b") == "a_b")
    }

    @Test func markupGetsAFigureWithTheCaretInTheCaption() {
        let s = ImageInsert.snippet(["images/cat photo.png"], mode: .markup)
        #expect(s.text == "#figure(\n  image(\"images/cat photo.png\", alt: \"\"),\n  caption: [],\n) <fig:cat-photo>")
        let caret = s.selection(insertedAt: 10)
        #expect((s.text as NSString).substring(to: caret.location - 10).hasSuffix("caption: ["))
        #expect(caret.length == 0)
    }

    @Test func folderChoiceAndNames() {
        #expect(ImageInsert.folder { _ in false } == "images")
        #expect(ImageInsert.folder { ["figures", "img"].contains($0) } == "img")
        #expect(ImageInsert.kebabName("My Photo (1).PNG") == "my-photo-1.png")
        #expect(ImageInsert.kebabName("Screenshot 2026-11-18 at 10.30.png") == "screenshot-2026-11-18-at-10-30.png")
        #expect(ImageInsert.kebabName("???.png") == "image.png")
    }

    @Test func labelsAreUniqueAgainstTheProjectAndEachOther() {
        #expect(ImageInsert.figureLabels(["a/cat.png", "b/cat.png"]) { $0 == "fig:cat" } == ["fig:cat-2", "fig:cat-3"])
        let s = ImageInsert.snippet(["cat.png"], mode: .markup) { $0 == "fig:cat" }
        #expect(s.text.hasSuffix("<fig:cat-2>"))
    }

    @Test func altTextEditsTheImageCall() {
        let text = ImageInsert.snippet(["x.png"], mode: .markup).text
        let f = FigureInfo.at(3, in: text)!
        #expect(f.value(.alt) == "")
        let r = f.edit(.alt, to: "A \"cat\"")!
        let out = (text as NSString).replacingCharacters(in: r.range, with: r.text)
        #expect(out.contains("alt: \"A \\\"cat\\\"\"") && FigureInfo.at(3, in: out)!.value(.alt) == "A \"cat\"")
    }

    @Test func otherModesGetImageCallsOrPaths() {
        #expect(ImageInsert.snippet(["a.png", "b \"q\".svg"], mode: .code).text == "image(\"a.png\"), image(\"b \\\"q\\\".svg\")")
        #expect(ImageInsert.snippet(["a.png"], mode: .math).text == "#image(\"a.png\")")
        #expect(ImageInsert.snippet(["a.png"], mode: .text).text == "a.png")
        let two = ImageInsert.snippet(["a.png", "b.png"], mode: .markup)
        #expect(two.text.components(separatedBy: "#figure(").count == 3)
        #expect(two.placeholders.count == 4)
    }

    @Test func outsideFilesAreCopiedInsideFilesStay() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "pics/in.png": "x"])
        let outside = FileManager.default.temporaryDirectory.appending(path: "img-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let photo = outside.appending(path: "photo.png")
        try Data("png".utf8).write(to: photo)

        // The temp folder is reached through /var -> /private/var: an inside file must still be recognised.
        let (paths, created) = try p.importImages([root.appending(path: "pics/in.png"), photo, photo])
        #expect(created.map(\.raw) == ["images/photo.png", "images/photo-2.png"])
        #expect(paths.map(\.raw) == ["pics/in.png", "images/photo.png", "images/photo-2.png"])
        #expect(try Data(contentsOf: root.appending(path: "images/photo-2.png")) == Data("png".utf8))
        #expect(FileManager.default.fileExists(atPath: photo.path))
        #expect(p.allFiles.map(\.raw).contains("images/photo-2.png"))
    }

    @Test func pastedDataGetsADatedFreeName() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": ""])
        let date = Date(timeIntervalSince1970: 1_795_000_000)
        let a = try p.addPastedImage(Data([1, 2]), at: date)
        let b = try p.addPastedImage(Data([3]), at: date)
        let name = ImageInsert.pastedName(at: date)
        #expect(a.raw == "images/\(name)")
        #expect(b.raw == "images/" + (name as NSString).deletingPathExtension + "-2.png")
        #expect(try Data(contentsOf: root.appending(path: b.raw)) == Data([3]))
        #expect(p.allFiles.contains(b))
    }
}
