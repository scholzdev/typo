import Foundation
import Testing
@testable import JSONRPC

/// Feeds `bytes` through `JSONRPCLines.read` in chunks, as a pipe would deliver them.
private func lines(_ chunks: [String], gap: Duration = .milliseconds(20)) async throws -> [String] {
    let pipe = Pipe()
    let out = Task.detached { () -> [String] in
        var got: [String] = []
        JSONRPCLines.read(pipe.fileHandleForReading.fileDescriptor) { got.append(String(decoding: $0, as: UTF8.self)) }
        return got
    }
    for c in chunks {
        try pipe.fileHandleForWriting.write(contentsOf: Data(c.utf8))
        try await Task.sleep(for: gap)
    }
    try pipe.fileHandleForWriting.close()
    return await out.value
}

@Suite(.timeLimit(.minutes(1))) struct JSONValueTests {
    @Test func jsonKeepsIntegersBooleansAndNewlines() throws {
        let v: JSONValue = ["id": 0, "on": true, "x": .double(1.5), "s": "a\nb", "n": nil]
        let data = v.json
        #expect(!data.contains(0x0A))
        #expect(try JSONValue(json: data) == v)
    }

    @Test func roundTripsNestedValuesAndUnicode() throws {
        let v: JSONValue = ["a": [1, .double(-2.5), "x", nil, true, ["deep": [[:], []]]],
                            "u": "h\u{e9}llo \u{1F600} \u{2028}\u{2029} \"q\" \\ /",
                            "big": .int(Int.max), "zero": .double(0.5), "neg": .int(-7)]
        #expect(try JSONValue(json: v.json) == v)
        #expect(String(decoding: v.json, as: UTF8.self).contains("/"))    // slashes stay unescaped
    }

    @Test func zeroOneAndBooleansStayApart() throws {
        let v = try JSONValue(json: Data(#"[0,1,false,true,1.0]"#.utf8))
        #expect(v.array?.prefix(4) == [.int(0), .int(1), .bool(false), .bool(true)])
        #expect(v.array?[4].int == 1)    // a whole double still reads as an Int
    }

    @Test func accessorsAnswerNilForTheWrongShape() {
        let v: JSONValue = ["s": "x", "n": 3]
        #expect(v["s"]?.string == "x" && v["s"]?.int == nil && v["n"]?.string == nil && v["missing"] == nil)
        #expect(JSONValue.string("x")["s"] == nil && JSONValue.null.array == nil)
        #expect(JSONValue.double(1.5).int == nil)
    }

    @Test func fragmentsAndGarbage() throws {
        #expect(try JSONValue(json: Data("null".utf8)) == .null)
        #expect(try JSONValue(json: Data("\"s\"".utf8)) == "s")
        #expect(throws: Error.self) { try JSONValue(json: Data("{nope".utf8)) }
    }
}

@Suite struct JSONRPCErrorTests {
    @Test func carriesCodeAndMessageWithStandardCodes() {
        let e = JSONRPCError(JSONRPCError.methodNotFound, "gone")
        #expect(e.code == -32601 && e.message == "gone" && e == JSONRPCError(-32601, "gone") && e != JSONRPCError(-32601, "x"))
        #expect(JSONRPCError.invalidParams == -32602 && JSONRPCError.internalError == -32603)
        #expect(JSONRPCInfo.protocolVersion == "2.0")
    }
}

@Suite(.timeLimit(.minutes(1))) struct JSONRPCLinesTests {
    @Test func splitsOnNewlineOnlyKeepingEmptyLinesAndCR() async throws {
        #expect(try await lines(["a\r\nb\n\n\nc\n"]) == ["a\r", "b", "", "", "c"])
    }

    @Test func unicodeLineSeparatorsInsideStringsDoNotSplit() async throws {
        let s = "{\"t\":\"x\u{2028}y\u{2029}z\u{85}\"}"
        #expect(try await lines([s + "\n" + s + "\n"]) == [s, s])
    }

    @Test func linesSplitAcrossReadsAreJoinedAndTheTailWithoutNewlineIsDropped() async throws {
        #expect(try await lines(["ab", "c\nd", "e\nf", "g"]) == ["abc", "de"])
    }

    @Test func longLinesBeyondOneReadSurvive() async throws {
        let big = String(repeating: "x", count: 200_000)
        #expect(try await lines([big + "\n"]) == [big])
    }
}
