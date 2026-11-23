import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite struct EditLogTests {
    let f = RelPath("a.typ")!
    let g = RelPath("b.typ")!
    func edit(_ n: UInt64, _ file: RelPath, _ loc: Int, _ len: Int, _ repl: String) -> Edit {
        Edit(seq: Seq(raw: n), file: file, range: NSRange(location: loc, length: len), replacement: repl, newLength: 0)
    }
    func log(_ edits: Edit...) -> EditLog { var l = EditLog(); edits.forEach { l.append($0) }; return l }
    let r = NSRange(location: 10, length: 5)

    @Test func insertBeforeShifts() {
        #expect(log(edit(2, f, 3, 0, "abc")).map(r, in: f, from: Seq(raw: 1)) == NSRange(location: 13, length: 5))
    }
    @Test func insertAtStartShifts() {
        #expect(log(edit(2, f, 10, 0, "xy")).map(r, in: f, from: Seq(raw: 1)) == NSRange(location: 12, length: 5))
    }
    @Test func insertAtEndAndAfterLeave() {
        #expect(log(edit(2, f, 15, 0, "xy")).map(r, in: f, from: Seq(raw: 1)) == r)
        #expect(log(edit(2, f, 40, 3, "")).map(r, in: f, from: Seq(raw: 1)) == r)
    }
    @Test func deleteAcrossIsNil() {
        #expect(log(edit(2, f, 8, 4, "")).map(r, in: f, from: Seq(raw: 1)) == nil)
        #expect(log(edit(2, f, 12, 0, "x")).map(r, in: f, from: Seq(raw: 1)) == nil)
        #expect(log(edit(2, f, 10, 5, "")).map(r, in: f, from: Seq(raw: 1)) == nil)
    }
    @Test func deleteBeforeShiftsBack() {
        #expect(log(edit(2, f, 2, 4, "")).map(r, in: f, from: Seq(raw: 1)) == NSRange(location: 6, length: 5))
    }
    @Test func otherFileIgnored() {
        #expect(log(edit(2, g, 0, 0, "zzzz")).map(r, in: f, from: Seq(raw: 1)) == r)
    }
    @Test func olderThanSeqIgnoredAndOrderComposes() {
        let l = log(edit(1, f, 0, 0, "old"), edit(2, f, 0, 0, "ab"), edit(3, f, 0, 2, "xyz"))
        #expect(l.map(r, in: f, from: Seq(raw: 1)) == NSRange(location: 13, length: 5))
        #expect(l.map(r, in: f, from: Seq(raw: 2)) == NSRange(location: 11, length: 5))
    }
    @Test func emojiOffsetsAreUTF16() {
        let text = "a😀b#undefinedfunc()"
        let ns = text as NSString
        let range = ns.range(of: "undefinedfunc")
        #expect(range.location == 5)   // emoji is two UTF-16 units
        let inserted = "😀😀"
        let l = log(edit(2, f, 1, 0, inserted))
        let mapped = l.map(range, in: f, from: Seq(raw: 1))!
        let after = ns.replacingCharacters(in: NSRange(location: 1, length: 0), with: inserted)
        #expect((after as NSString).substring(with: mapped) == "undefinedfunc")
        // deleting the emoji (2 units) before the range shifts back by 2
        let l2 = log(edit(2, f, 1, 2, ""))
        #expect(l2.map(range, in: f, from: Seq(raw: 1))?.location == 3)
    }
    @Test func trimDropsCovered() {
        var l = log(edit(1, f, 0, 0, "a"), edit(2, f, 0, 0, "b"))
        l.trim(through: Seq(raw: 1))
        #expect(l.entries.count == 1)
    }
}
