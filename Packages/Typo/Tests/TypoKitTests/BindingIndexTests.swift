import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite struct BindingIndexTests {
    /// An index over `files` (iteration order is sorted by path) and a way to point at the n-th occurrence of a snippet.
    struct Fixture {
        let index: BindingIndex
        let texts: [String: String]

        init(_ texts: [String: String]) {
            self.texts = texts
            index = BindingIndex.build(texts.sorted { $0.key < $1.key }.map { (RelPath($0.key)!, $0.value) })
        }

        /// Offset of the `nth` (0-based) occurrence of `needle` in `file`, plus `inner` characters.
        func at(_ file: String, _ needle: String, _ nth: Int = 0, inner: Int = 0) -> Int {
            var from = texts[file]!.startIndex
            var found: Range<String.Index>?
            for _ in 0...nth {
                found = texts[file]![from...].range(of: needle)
                if let f = found { from = f.upperBound }
            }
            return (texts[file]!.utf16.distance(from: texts[file]!.startIndex, to: found!.lowerBound)) + inner
        }

        func symbol(_ file: String, _ needle: String, _ nth: Int = 0) -> BindingSymbol? { index.symbol(in: RelPath(file)!, at: at(file, needle, nth)) }

        func refs(_ s: BindingSymbol) -> Set<String> {
            Set(index.references(of: s).map { r in
                return "\(r.file.raw):\(r.range.location)"
            })
        }

        /// `file:offset` for the n-th occurrences given as (file, needle, nth).
        func site(_ file: String, _ needle: String, _ nth: Int = 0) -> String { "\(file):\(at(file, needle, nth))" }
    }

    @Test func localLet() {
        let f = Fixture(["m.typ": "#let x = 1\n#x + #x\n"])
        let d = f.symbol("m.typ", "x")
        #expect(d?.name == "x")
        #expect(f.symbol("m.typ", "x", 1) == d)
        #expect(f.symbol("m.typ", "x", 2) == d)
        #expect(f.refs(d!) == [f.site("m.typ", "x", 1), f.site("m.typ", "x", 2)])
    }

    @Test func useBeforeDefinitionIsNotBound() {
        let f = Fixture(["m.typ": "#x\n#let x = 1\n#let y = x\n"])
        #expect(f.symbol("m.typ", "x", 0) == nil)
        #expect(f.symbol("m.typ", "x", 2) == f.symbol("m.typ", "x", 1))
    }

    @Test func letInitSeesTheOuterBinding() {
        let f = Fixture(["m.typ": "#let x = 1\n#let x = x + 1\n#x\n"])
        let first = f.symbol("m.typ", "x", 0)
        #expect(f.symbol("m.typ", "x", 2) == first)             // the x inside the second initializer
        #expect(f.symbol("m.typ", "x", 3) == f.symbol("m.typ", "x", 1))
        #expect(first != f.symbol("m.typ", "x", 1))
    }

    @Test func shadowingInNestedBlock() {
        let f = Fixture(["m.typ": "#let x = 1\n#{ let x = 2; x }\n#x\n"])
        let outer = f.symbol("m.typ", "x", 0)
        let inner = f.symbol("m.typ", "x", 1)
        #expect(outer != inner)
        #expect(f.symbol("m.typ", "x", 2) == inner)
        #expect(f.symbol("m.typ", "x", 3) == outer)
        #expect(f.refs(outer!) == [f.site("m.typ", "x", 3)])
    }

    @Test func functionAndRecursion() {
        let f = Fixture(["m.typ": "#let fact(n) = if n <= 1 { 1 } else { n * fact(n - 1) }\n#fact(3)\n"])
        let d = f.symbol("m.typ", "fact")
        #expect(f.symbol("m.typ", "fact", 1) == d)
        #expect(f.symbol("m.typ", "fact", 2) == d)
        #expect(f.refs(d!).count == 2)
    }

    @Test func parametersDoNotLeak() {
        let f = Fixture(["m.typ": "#let f(a, b: 2) = a + b\n#a\n#f(1, b: 3)\n"])
        let a = f.symbol("m.typ", "a")
        #expect(a != nil)
        #expect(f.symbol("m.typ", "a", 1) == a)       // the use in the body
        #expect(f.symbol("m.typ", "a", 2) == nil)     // outside the function
        #expect(f.symbol("m.typ", "b", 1) == f.symbol("m.typ", "b"))
        #expect(f.refs(f.symbol("m.typ", "b")!).count == 1)   // the named argument key `b: 3` is not a use
    }

    @Test func closureParameter() {
        let f = Fixture(["m.typ": "#let g = z => z + 1\n#z\n"])
        let z = f.symbol("m.typ", "z")
        #expect(f.symbol("m.typ", "z", 1) == z)
        #expect(f.symbol("m.typ", "z", 2) == nil)
    }

    @Test func forLoopVariable() {
        let f = Fixture(["m.typ": "#let k = 0\n#for k in range(3) [#k]\n#k\n"])
        let outer = f.symbol("m.typ", "k")
        let loop = f.symbol("m.typ", "k", 1)
        #expect(outer != loop)
        #expect(f.symbol("m.typ", "k", 2) == loop)
        #expect(f.symbol("m.typ", "k", 3) == outer)
    }

    @Test func destructuring() {
        let f = Fixture(["m.typ": "#let (a, b) = (1, 2)\n#a #b\n#for (k, v) in (:) [#k #v]\n"])
        #expect(f.symbol("m.typ", "a", 1) == f.symbol("m.typ", "a"))
        #expect(f.symbol("m.typ", "b", 1) == f.symbol("m.typ", "b"))
        #expect(f.symbol("m.typ", "v", 1) == f.symbol("m.typ", "v"))
    }

    @Test func fieldAndNamedKeysAreNotUses() {
        let f = Fixture(["m.typ": "#let x = 1\n#let d = (x: 2)\n#d.x\n#text(x: 3)[a]\n"])
        let x = f.symbol("m.typ", "x")
        #expect(f.refs(x!).isEmpty)
        #expect(f.symbol("m.typ", "x", 1) == nil)     // dictionary key
        #expect(f.symbol("m.typ", "x", 2) == nil)     // field of a value, not of a module
    }

    @Test func importNamedItems() {
        let f = Fixture(["a.typ": "#let f(x) = x\n#let g = 1\n", "main.typ": "#import \"a.typ\": f\n#f(1) #f(2)\n#let g = 3\n#g\n"])
        let def = f.symbol("a.typ", "f")
        #expect(def?.file == RelPath("a.typ"))
        #expect(f.symbol("main.typ", "f", 1) == def)                  // use
        #expect(f.symbol("main.typ", "f", 0) == def)                  // import item
        #expect(f.refs(def!) == [f.site("main.typ", "f", 0), f.site("main.typ", "f", 1), f.site("main.typ", "f", 2)])
        #expect(f.symbol("main.typ", "g", 1)?.file == RelPath("main.typ"))   // the local g, not a.typ's
    }

    @Test func importWildcard() {
        let f = Fixture(["a.typ": "#let f = 1\n", "main.typ": "#import \"a.typ\": *\n#f\n"])
        #expect(f.symbol("main.typ", "f") == f.symbol("a.typ", "f"))
        #expect(f.symbol("main.typ", "f")?.file == RelPath("a.typ"))
    }

    @Test func importAlias() {
        let f = Fixture(["a.typ": "#let f = 1\n", "main.typ": "#import \"a.typ\": f as g\n#g #f\n"])
        let orig = f.symbol("a.typ", "f")
        let alias = f.symbol("main.typ", "g")
        #expect(alias?.file == RelPath("main.typ"))
        #expect(alias != orig)
        #expect(f.symbol("main.typ", "g", 1) == alias)
        #expect(f.symbol("main.typ", "f", 0) == orig)                 // the original name in the item
        #expect(f.symbol("main.typ", "f", 1) == nil)                  // `f` is not bound here
        #expect(f.refs(orig!) == [f.site("main.typ", "f", 0)])
        #expect(f.refs(alias!) == [f.site("main.typ", "g", 1)])
    }

    @Test func moduleAlias() {
        let f = Fixture(["a.typ": "#let f = 1\n", "main.typ": "#import \"a.typ\" as m\n#m.f #m.f\n"])
        let def = f.symbol("a.typ", "f")
        #expect(f.symbol("main.typ", "f", 0) == def)
        #expect(f.refs(def!).count == 2)
        let m = f.index.symbol(in: RelPath("main.typ")!, at: f.at("main.typ", "as m", inner: 3))
        #expect(m?.file == RelPath("main.typ"))
        #expect(f.refs(m!).count == 2)
    }

    @Test func implicitModuleName() {
        let f = Fixture(["a.typ": "#let f = 1\n", "main.typ": "#import \"a.typ\"\n#a.f\n"])
        #expect(f.symbol("main.typ", "f") == f.symbol("a.typ", "f"))
        let a = f.symbol("main.typ", "a")
        #expect(a != nil)
        #expect(a.map { f.index.isRenameable($0) } == false)
    }

    @Test func relativePathsInSubfolders() {
        let f = Fixture([
            "lib/util.typ": "#let helper = 1\n",
            "lib/inner/deep.typ": "#import \"../util.typ\": helper\n#helper\n",
            "doc/main.typ": "#import \"../lib/util.typ\": helper\n#import \"/lib/util.typ\": helper as h2\n#helper #h2\n",
        ])
        let def = f.symbol("lib/util.typ", "helper")
        #expect(f.symbol("lib/inner/deep.typ", "helper", 1) == def)
        #expect(f.symbol("doc/main.typ", "helper", 2) == def)
        #expect(f.refs(def!).count == 5)
    }

    @Test func packagesAreIgnored() {
        let f = Fixture(["main.typ": "#import \"@preview/cetz:0.3.0\": canvas\n#canvas\n"])
        let s = f.symbol("main.typ", "canvas", 1)
        #expect(s?.file == RelPath("main.typ"))      // the import item itself
        #expect(f.index.hasSite(in: RelPath("main.typ")!, at: f.at("main.typ", "canvas", 1)))
    }

    @Test func reExportedImport() {
        let f = Fixture(["a.typ": "#let f = 1\n", "b.typ": "#import \"a.typ\": f\n", "main.typ": "#import \"b.typ\": f\n#f\n"])
        #expect(f.symbol("main.typ", "f", 1) == f.symbol("a.typ", "f"))
    }

    @Test func renameAcrossFiles() throws {
        let f = Fixture(["a.typ": "#let f(x) = x\n", "main.typ": "#import \"a.typ\": f\n#f(1)\n"])
        let def = try #require(f.symbol("a.typ", "f"))
        let edits = f.index.rename(def, to: "ff")
        #expect(edits[RelPath("a.typ")!]?.map(\.range) == [NSRange(location: 5, length: 1)])
        #expect(Set(edits[RelPath("main.typ")!]?.map(\.range.location) ?? []) == [f.at("main.typ", "f", 0), f.at("main.typ", "f", 1)])
        #expect(edits.values.joined().allSatisfy { $0.text == "ff" })
    }

    @Test func renameAliasSemantics() throws {
        let f = Fixture(["a.typ": "#let yy = 1\n", "main.typ": "#import \"a.typ\": yy as zz\n#zz\n"])
        let orig = try #require(f.symbol("a.typ", "yy"))
        let origEdits = f.index.rename(orig, to: "w")
        #expect(origEdits[RelPath("main.typ")!]?.map(\.range.location) == [f.at("main.typ", "yy")])   // the item name only
        let alias = try #require(f.symbol("main.typ", "zz"))
        let aliasEdits = f.index.rename(alias, to: "q")
        #expect(aliasEdits[RelPath("a.typ")!] == nil)
        #expect(Set(aliasEdits[RelPath("main.typ")!]?.map(\.range.location) ?? []) == [f.at("main.typ", "zz"), f.at("main.typ", "zz", 1)])
    }

    @Test func validation() throws {
        let f = Fixture(["m.typ": "#let a = 1\n#let b = 2\n#let c(a) = a\n#a #b\n"])
        let a = try #require(f.symbol("m.typ", "a"))
        #expect(f.index.validate("", for: a) != nil)
        #expect(f.index.validate("a", for: a) != nil)
        #expect(f.index.validate("1x", for: a) != nil)
        #expect(f.index.validate("x y", for: a) != nil)
        #expect(f.index.validate("let", for: a) != nil)
        #expect(f.index.validate("b", for: a) != nil)         // collides with another visible binding
        #expect(f.index.validate("new-name_1", for: a) == nil)
        #expect(f.index.validate("é", for: a) == nil)
    }
}
