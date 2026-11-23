import Foundation
import Testing
import JSONRPC
@testable import MCPProtocol

@MainActor final class StubTools: MCPToolProvider {
    var tools = [MCPTool(name: "echo", description: "Echoes.", inputSchema: ["type": "object"])]
    var calls: [String] = []
    func call(_ name: String, arguments: JSONValue) async -> MCPToolResult {
        calls.append(name)
        switch name {
        case "echo": return MCPToolResult(text: arguments["text"]?.string ?? "")
        case "shot": return MCPToolResult(text: "img", png: Data([0x89, 0x50]))
        default: return MCPToolResult(text: "No tool \(name).", isError: true)
        }
    }
}

@MainActor private func send(_ s: MCPServer, _ line: String) async throws -> JSONValue? {
    try await s.handle(line: Data(line.utf8)).map { try JSONValue(json: $0) }
}

@MainActor @Suite(.timeLimit(.minutes(1))) struct MCPServerTests {
    let stub = StubTools()
    var server: MCPServer { MCPServer(name: "typo", version: "test", tools: stub) }

    @Test func initializeAgreesOnAVersionItSpeaks() async throws {
        let s = server
        let old = try #require(try await send(s, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}"#))
        #expect(old["id"] == 1 && old["result"]?["protocolVersion"] == "2024-11-05")
        #expect(old["result"]?["serverInfo"]?["name"] == "typo" && old["result"]?["capabilities"]?["tools"] == [:])
        let future = try #require(try await send(s, #"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"2099-01-01"}}"#))
        #expect(future["id"] == "a" && future["result"]?["protocolVersion"] == "2025-06-18")
    }

    @Test func notificationsMalformedLinesAndUnknownMethods() async throws {
        let s = server
        #expect(try await send(s, #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
        #expect(try await send(s, "{not json") == nil)
        #expect(try await send(s, #"{"jsonrpc":"2.0","id":2,"method":"ping"}"#)?["result"] == [:])
        let unknown = try #require(try await send(s, #"{"jsonrpc":"2.0","id":3,"method":"resources/list"}"#))
        #expect(unknown["error"]?["code"]?.int == -32601 && unknown["result"] == nil)
    }

    @Test func listsToolsWithTheirSchema() async throws {
        let tools = try #require(try await send(server, #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)?["result"]?["tools"]?.array)
        #expect(tools == [["name": "echo", "description": "Echoes.", "inputSchema": ["type": "object"]]])
    }

    @Test func callsFrameTextImagesAndErrorsAsResults() async throws {
        let s = server
        func call(_ name: String, _ args: String = "{}") async throws -> JSONValue {
            try #require(try await send(s, #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"\#(name)","arguments":\#(args)}}"#)?["result"])
        }
        let echo = try await call("echo", #"{"text":"hi"}"#)
        #expect(echo["content"] == [["type": "text", "text": "hi"]] && echo["isError"] == false)
        let shot = try await call("shot")
        #expect(shot["content"]?.array?.count == 2 && shot["content"]?.array?[1]["mimeType"] == "image/png")
        #expect(shot["content"]?.array?[1]["data"]?.string == Data([0x89, 0x50]).base64EncodedString())
        let bad = try await call("rm_rf")
        #expect(bad["isError"] == true && bad["content"]?.array?.first?["text"] == "No tool rm_rf.")
        #expect(stub.calls == ["echo", "shot", "rm_rf"])
    }
}
