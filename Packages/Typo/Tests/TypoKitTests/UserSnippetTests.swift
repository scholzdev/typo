import Testing
import Foundation
import TypoTestSupport
@testable import TypoKit

@MainActor @Suite struct UserSnippetTests {
    private func defaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "usersnippets-\(UUID().uuidString)")!
        return d
    }

    @Test func persistsRoundTrip() {
        let d = defaults()
        let store = UserSnippetStore(defaults: d)
        let s = store.add(UserSnippet(title: "Frac", summary: "x", prefix: "fr", body: "$ ${1:a}/${2:b} $", isBlock: false))
        var edited = s
        edited.title = "Fraction"
        store.update(edited)
        let again = UserSnippetStore(defaults: d)
        #expect(again.snippets == [edited])
        again.delete(s.id)
        #expect(UserSnippetStore(defaults: d).snippets.isEmpty)
    }

    @Test func mapsToLibrary() {
        let s = UserSnippet(title: "T", prefix: "t", body: "#f(${1:a}, ${1})", isBlock: false)
        let l = s.librarySnippet
        #expect(l.id == "user-\(s.id.uuidString)")
        #expect(l.category == "User" && l.symbol == "curlybraces" && !l.isBlock)
        #expect(l.plainText == "#f(a, a)")
        let store = UserSnippetStore(defaults: defaults())
        store.add(s)
        #expect(store.librarySnippet(withID: l.id) == l)
    }

    @Test func prefixCompletion() {
        let store = UserSnippetStore(defaults: defaults())
        store.add(UserSnippet(title: "A", prefix: "fig"))
        store.add(UserSnippet(title: "B", prefix: "FigX"))
        store.add(UserSnippet(title: "C", prefix: ""))
        #expect(store.completions(matching: "fi").map(\.title) == ["A", "B"])
        #expect(store.completions(matching: "figx").map(\.title) == ["B"])
        #expect(store.completions(matching: "").isEmpty)
    }
}
