import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit

struct GitGutterTests {
    @Test func unchangedHasNoMarks() {
        #expect(GitGutterMarks.compute(base: "a\nb\n", current: "a\nb\n").isEmpty)
    }

    @Test func addedModifiedAndDeleted() {
        let base = "a\nb\nc\nd\ne\n"
        // b modified, a line added after c, e deleted
        let m = GitGutterMarks.compute(base: base, current: "a\nB\nc\nnew\nd\n")
        #expect(m.lines == [2: .modified, 4: .added])
        #expect(m.deletedAfter == [5])
    }

    @Test func deletionAtTheStartAndAdditionAtTheEnd() {
        let m = GitGutterMarks.compute(base: "x\na\nb", current: "a\nb\nc\nd")
        #expect(m.deletedAfter == [0])
        #expect(m.lines == [3: .added, 4: .added])
    }

    @Test func newFileIsAllAdded() {
        let m = GitGutterMarks.compute(base: "", current: "a\nb")
        #expect(m.lines == [1: .added, 2: .added] && m.deletedAfter.isEmpty)
    }
}
