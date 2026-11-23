import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite(.serialized) @MainActor struct CodeBookmarkTests {
    private func rel(_ s: String) -> RelPath { RelPath(s)! }
    private func replace(_ b: Buffer, _ r: NSRange, _ s: String) { b.storage.replaceCharacters(in: r, with: s) }

    @Test func shiftRules() {
        let line = NSRange(location: 10, length: 6)                 // "hello\n" at 10
        #expect(CodeBookmark.shift(line, by: NSRange(location: 0, length: 0), newLength: 3) == NSRange(location: 13, length: 6))
        #expect(CodeBookmark.shift(line, by: NSRange(location: 10, length: 0), newLength: 1) == NSRange(location: 11, length: 6))   // Return at column 0
        #expect(CodeBookmark.shift(line, by: NSRange(location: 9, length: 1), newLength: 0) == NSRange(location: 9, length: 6))     // joined to the line above
        #expect(CodeBookmark.shift(line, by: NSRange(location: 12, length: 0), newLength: 2) == NSRange(location: 10, length: 8))   // typing on the line
        #expect(CodeBookmark.shift(line, by: NSRange(location: 16, length: 4), newLength: 0) == line)                               // after it
        #expect(CodeBookmark.shift(line, by: NSRange(location: 10, length: 6), newLength: 0) == nil)                                // the line deleted
        #expect(CodeBookmark.shift(line, by: NSRange(location: 5, length: 15), newLength: 1) == nil)
        #expect(CodeBookmark.shift(line, by: NSRange(location: 10, length: 5), newLength: 2) == NSRange(location: 10, length: 3))   // text replaced, break kept
    }

    @Test func followsEditsThroughTheBuffer() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "one\ntwo\nthree\nfour\n"])
        let a = try await p.open(rel("a.typ"))
        p.toggleBookmark(rel("a.typ"), line: 2)                     // "three"
        replace(a, NSRange(location: 0, length: 0), "zero\n")
        #expect(p.bookmarks.map(\.line) == [3])
        replace(a, NSRange(location: 15, length: 0), "3")           // typing on "three"
        #expect(p.bookmarks.map(\.line) == [3])
        replace(a, NSRange(location: 0, length: 9), "")             // "zero\none\n" deleted
        #expect(p.bookmarks.map(\.line) == [1])
        let three = (a.storage.string as NSString).lineRange(for: NSRange(location: 5, length: 0))
        replace(a, three, "")
        #expect(p.bookmarks.isEmpty)
    }

    /// A reload or reformat replaces the whole text in one edit; that is no deletion, so the bookmark stays on its line.
    @Test func survivesWholeTextReplacement() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "one\ntwo\nthree\nfour\n"])
        let a = try await p.open(rel("a.typ"))
        p.toggleBookmark(rel("a.typ"), line: 2)
        replace(a, NSRange(location: 0, length: a.storage.length), "one\ntwo\nthree!\nfour\n")
        #expect(p.bookmarks.map(\.line) == [2])
        replace(a, NSRange(location: 0, length: a.storage.length), "one\n")      // shorter text: clamped to its last line
        #expect(p.bookmarks.map(\.line) == [0])
    }

    @Test func persistsAndReanchorsOnOpen() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "one\ntwo\n"])
        p.toggleBookmark(rel("a.typ"), line: 1)                     // not open yet: no anchor until it is
        p.updateBookmark(p.bookmarks[0].id) { $0.note = "check"; $0.done = true }
        let saved = BookmarkStore(p.id).load()
        #expect(saved.count == 1 && saved[0].note == "check" && saved[0].done && saved[0].line == 1)
        let a = try await p.open(rel("a.typ"))
        replace(a, NSRange(location: 0, length: 0), "x\n")
        #expect(p.bookmarks.map(\.line) == [2] && BookmarkStore(p.id).load().map(\.line) == [2])
        #expect(await p.bookmarkSnippets()[p.bookmarks[0].id] == "two")
        p.toggleBookmark(rel("a.typ"), line: 2)
        #expect(p.bookmarks.isEmpty && BookmarkStore(p.id).load().isEmpty)
    }

    @Test func nextAndPreviousWrapAcrossFiles() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "1\n2\n3\n", "b.typ": "1\n"])
        p.toggleBookmark(rel("b.typ"), line: 0)
        p.toggleBookmark(rel("a.typ"), line: 2)
        p.toggleBookmark(rel("a.typ"), line: 0)
        #expect(p.adjacentBookmark(from: rel("a.typ"), line: 0, forward: true)?.line == 2)
        #expect(p.adjacentBookmark(from: rel("a.typ"), line: 2, forward: true)?.path == rel("b.typ"))
        let wrapped = p.adjacentBookmark(from: rel("b.typ"), line: 0, forward: true)
        #expect(wrapped?.path == rel("a.typ") && wrapped?.line == 0)
        #expect(p.adjacentBookmark(from: rel("a.typ"), line: 0, forward: false)?.path == rel("b.typ"))
    }

    @Test func followsRenames() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "1\n"])
        p.toggleBookmark(rel("a.typ"), line: 0)
        try await p.relocate(rel("a.typ"), to: rel("b.typ"))
        #expect(p.bookmarks.map(\.path) == [rel("b.typ")])
    }

    @Test func decodesTheFormatFromBeforeGroups() throws {
        var saved = CodeBookmark(path: rel("a.typ"), line: 3)
        saved.note = "n"; saved.done = true
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
        json["group"] = nil; json["isFile"] = nil
        let b = try JSONDecoder().decode([CodeBookmark].self, from: JSONSerialization.data(withJSONObject: [json]))
        #expect(b.count == 1 && b[0].line == 3 && b[0].note == "n" && b[0].group == "" && !b[0].isFile)
        let round = try JSONDecoder().decode([CodeBookmark].self, from: JSONEncoder().encode(b))
        #expect(round == b)
    }

    @Test func fileBookmarksIgnoreEditsFollowRenamesAndGoWithTheFile() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "one\n"])
        p.addFileBookmark(rel("a.typ"))
        p.addFileBookmark(rel("a.typ"))
        #expect(p.bookmarks.count == 1 && p.fileBookmark(rel("a.typ")) != nil && p.bookmarkedLines(in: rel("a.typ")).isEmpty)
        let a = try await p.open(rel("a.typ"))
        replace(a, NSRange(location: 0, length: a.storage.length), "")
        #expect(p.bookmarks.count == 1)
        p.toggleBookmark(rel("a.typ"), line: 0)                     // a line bookmark beside it
        #expect(p.bookmarks.count == 2 && p.sortedBookmarks.first?.isFile == true)
        try await p.relocate(rel("a.typ"), to: rel("b.typ"))
        #expect(p.fileBookmark(rel("b.typ")) != nil && BookmarkStore(p.id).load().contains { $0.isFile && $0.path == rel("b.typ") })
        try await p.moveToTrash(rel("b.typ"))
        #expect(p.bookmarks.isEmpty)
    }

    @Test func groupsAreNamesOnTheirBookmarks() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "1\n2\n3\n"])
        for l in 0..<3 { p.toggleBookmark(rel("a.typ"), line: l) }
        let ids = p.sortedBookmarks.map(\.id)
        #expect(p.newBookmarkGroupName == "New Group")
        p.moveBookmarks([ids[0], ids[1]], toGroup: "New Group")
        #expect(p.bookmarkGroups == ["New Group"] && p.newBookmarkGroupName == "New Group 2")
        p.moveBookmarks([ids[1]], toGroup: "Todo")
        p.renameBookmarkGroup("New Group", to: "Intro")
        #expect(p.bookmarkGroups == ["Intro", "Todo"] && BookmarkStore(p.id).load().map(\.group).sorted() == ["", "Intro", "Todo"])
        p.renameBookmarkGroup("Todo", to: "")                       // delete: the bookmark stays, ungrouped
        #expect(p.bookmarkGroups == ["Intro"] && p.bookmarks.count == 3)
    }
}
