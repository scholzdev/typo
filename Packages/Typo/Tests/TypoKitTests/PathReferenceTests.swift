import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite @MainActor struct PathReferenceTests {
    private func rel(_ s: String) -> RelPath { RelPath(s)! }

    /// `text` (in `file` before the move) with the updates for moving `old` to `new` applied.
    private func updated(_ text: String, in file: String, _ old: String, _ new: String, existing: [String]) -> String {
        let edits = PathReferences.edits(in: text, of: rel(file), moving: rel(old), to: rel(new), existing: Set(existing.map(rel)))
        let s = NSMutableString(string: text)
        for e in edits.sorted(by: { $0.range.location > $1.range.location }) { s.replaceCharacters(in: e.range, with: e.text) }
        return s as String
    }

    @Test func renamedFileInEveryStyle() {
        let files = ["main.typ", "a.typ", "sub", "sub/x.typ"]
        #expect(updated("#include \"a.typ\"\n#include \"./a.typ\"\n#include \"/a.typ\"", in: "main.typ", "a.typ", "b.typ", existing: files)
                == "#include \"b.typ\"\n#include \"./b.typ\"\n#include \"/b.typ\"")
        #expect(updated("#include \"../a.typ\"", in: "sub/x.typ", "a.typ", "b.typ", existing: files) == "#include \"../b.typ\"")
    }

    @Test func movedFolderUpdatesStringsPointingIntoIt() {
        let files = ["main.typ", "figs", "figs/cat.png", "chapters", "chapters/c.typ", "assets"]
        #expect(updated("#image(\"figs/cat.png\") #image(\"/figs/cat.png\")", in: "main.typ", "figs", "assets/figs", existing: files)
                == "#image(\"assets/figs/cat.png\") #image(\"/assets/figs/cat.png\")")
        #expect(updated("#image(\"../figs/cat.png\")", in: "chapters/c.typ", "figs", "assets/figs", existing: files)
                == "#image(\"../assets/figs/cat.png\")")
    }

    @Test func movedFileFixesItsOwnRelativePaths() {
        let files = ["main.typ", "intro.typ", "chapters", "chapters/c.typ", "chapters/sec.typ", "chapters/fig.png"]
        #expect(updated("#include \"../intro.typ\"\n#include \"sec.typ\"\n#image(\"/chapters/fig.png\")", in: "chapters/c.typ",
                        "chapters/c.typ", "c.typ", existing: files)
                == "#include \"intro.typ\"\n#include \"chapters/sec.typ\"\n#image(\"/chapters/fig.png\")")
    }

    @Test func filesMovingTogetherKeepTheirRelativeStrings() {
        let files = ["main.typ", "ch", "ch/a.typ", "ch/b.typ", "part"]
        #expect(updated("#include \"b.typ\"\n#include \"/ch/b.typ\"\n#include \"../main.typ\"", in: "ch/a.typ", "ch", "part/ch", existing: files)
                == "#include \"b.typ\"\n#include \"/part/ch/b.typ\"\n#include \"../../main.typ\"")
    }

    @Test func nonPathsPackagesCommentsAndMarkupStay() {
        let text = """
        #let s = "hello"
        #import "@preview/cetz:0.3.0"
        // see "a.typ"
        He said "a.typ".
        #link("https://a.typ")
        #let e = ""
        #let up = "../a.typ"
        #include "a.typ"
        """
        let files = ["main.typ", "a.typ"]
        #expect(updated(text, in: "main.typ", "a.typ", "b.typ", existing: files)
                == text.replacingOccurrences(of: "#include \"a.typ\"", with: "#include \"b.typ\""))
    }

    @Test func renameUpdatesOpenAndClosedFilesOneUndoStepEach() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "#include \"ch/a.typ\"\n", "ch/a.typ": "= A\n#image(\"../fig.png\")\n",
                                                       "ch/b.typ": "#include \"a.typ\"\n#include \"a.typ\"\n", "fig.png": "x"])
        let m = try await p.open(rel("main.typ"))
        m.undoManager.groupsByEvent = false
        type(m, "// draft\n", at: 0)
        let u = p.referenceUpdates(moving: rel("ch/a.typ"), to: rel("ch/intro.typ"))
        #expect(u.count == 3 && Set(u.edits.keys) == [rel("main.typ"), rel("ch/b.typ")])
        try await p.rename(rel("ch/a.typ"), to: "intro.typ")
        type(m, "X", at: 0)                                     // typed after the plan: the ranges are recomputed
        try await p.updateReferences(u)
        #expect(m.storage.string == "X// draft\n#include \"ch/intro.typ\"\n")
        let b = try #require(p.buffer(for: rel("ch/b.typ")))
        #expect(b.storage.string == "#include \"intro.typ\"\n#include \"intro.typ\"\n")
        #expect(p.buffer(for: rel("ch/intro.typ")) == nil)      // its own relative path still works: not even opened
        b.undoManager.undo()
        #expect(b.storage.string == "#include \"a.typ\"\n#include \"a.typ\"\n")
        m.undoManager.undo()
        #expect(m.storage.string == "X// draft\n#include \"ch/a.typ\"\n")
    }
}

@Suite struct PathTargetTests {
    private let main = RelPath("main.typ")!
    private let existing: Set<RelPath> = Set(["img/a.png", "kapitel.typ", "x.typ"].map { RelPath($0)! })
    private func target(_ text: String, at marker: String) -> RelPath? {
        let i = (text as NSString).range(of: marker).location
        return PathReferences.target(in: text, of: main, at: i, existing: existing)?.target
    }

    @Test func existingTargets() {
        #expect(target("#image(\"img/a.png\")", at: "a.png") == RelPath("img/a.png")!)
        #expect(target("#include \"kapitel.typ\"", at: "kapitel") == RelPath("kapitel.typ")!)
        #expect(target("#include \"/x.typ\"", at: "x.typ") == RelPath("x.typ")!)
    }

    @Test func noTarget() {
        #expect(target("#image(\"img/none.png\")", at: "none") == nil)
        #expect(target("#import \"@preview/x:1.0.0\"", at: "preview") == nil)
        #expect(target("#link(\"https://x.typ\")", at: "https") == nil)
        #expect(target("#image(\"img/a.png\")", at: "image") == nil)
    }
}
