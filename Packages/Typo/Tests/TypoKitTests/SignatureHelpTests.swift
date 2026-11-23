import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite(.serialized) @MainActor struct SignatureHelpTests {
    static let main = RelPath("main.typ")!
    static let text = """
    #let greet(name, loud: false, ..rest) = name
    #text(red, size: 12pt)[body]
    #greet("a", loud: true, 1, 2)
    #calc.max(1, 2)
    #figure(image("a.png"), caption: [a caption])
    #str(1)
    plain (not a call)

    """

    private func help(after marker: String, offset: Int = 0) async throws -> SignatureHelp? {
        let (p, _) = try await TestEnv.project(files: ["main.typ": Self.text])
        _ = try await p.open(Self.main)
        _ = await p.settle()
        let at = (Self.text as NSString).range(of: marker).location + (marker as NSString).length + offset
        return await p.signatureHelp(in: Self.main, at: at)
    }

    @Test func builtinPositionalAndNamedArguments() async throws {
        let first = try #require(try await help(after: "#text("))
        #expect(first.name == "text")
        #expect(first.activeParameter?.name == "body" || first.activeParameter?.positional == true)
        let size = try #require(try await help(after: "size: 1"))
        #expect(size.activeParameter?.name == "size")
        #expect(size.activeParameter?.label.hasPrefix("size: ") == true)
        #expect(size.activeParameter?.docs.isEmpty == false)
    }

    @Test func projectFunctionsFillPositionalThenSink() async throws {
        let first = try #require(try await help(after: "#greet(\""))
        #expect(first.name == "greet")
        #expect(first.params.map(\.label) == ["name", "loud: false", "..rest"])
        #expect(first.activeParameter?.name == "name")
        #expect(try await help(after: "loud: t")?.activeParameter?.name == "loud")
        // After `name` the remaining positional arguments all go into the sink.
        #expect(try await help(after: "true, 1, ")?.activeParameter?.name == "rest")
    }

    @Test func moduleFieldsAndTypeConstructors() async throws {
        #expect(try await help(after: "#calc.max(")?.name == "max")
        #expect(try await help(after: "#str(")?.name == "str")
    }

    @Test func nothingOutsideTheParenthesesOrInsideContent() async throws {
        #expect(try await help(after: "#text", offset: 0) == nil)
        #expect(try await help(after: "[bo") == nil)               // trailing content block
        #expect(try await help(after: "[a cap") == nil)            // content block inside an argument
        #expect(try await help(after: "plain (no") == nil)
        #expect(try await help(after: "12pt)") == nil)
    }

    @Test func nestedCallsAnswerForTheInnermost() async throws {
        #expect(try await help(after: "image(\"a")?.name == "image")
        let caption = try #require(try await help(after: "caption: "))
        #expect(caption.name == "figure")
        #expect(caption.activeParameter?.name == "caption")
    }
}
