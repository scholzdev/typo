import Foundation
import JSONRPC

/// A tool as `tools/list` announces it.
public struct MCPTool: Sendable, Equatable {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue
    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name; self.description = description; self.inputSchema = inputSchema
    }
}

/// What a tool call returns: text, an optional PNG, and whether the call failed (a result, not a protocol error).
public struct MCPToolResult: Sendable, Equatable {
    public var text: String
    public var png: Data?
    public var isError: Bool
    public init(text: String, png: Data? = nil, isError: Bool = false) { self.text = text; self.png = png; self.isError = isError }
}

/// The tools a server offers.
@MainActor public protocol MCPToolProvider: AnyObject {
    var tools: [MCPTool] { get }
    func call(_ name: String, arguments: JSONValue) async -> MCPToolResult
}

/// The server side of the Model Context Protocol over newline-framed JSON-RPC: version negotiation, ping, and the
/// tools/list and tools/call framing around a `MCPToolProvider`. The caller hands it each stdin line.
@MainActor public final class MCPServer {
    private let name: String
    private let version: String
    private let provider: any MCPToolProvider

    public init(name: String, version: String, tools provider: any MCPToolProvider) {
        self.name = name; self.version = version; self.provider = provider
    }

    /// The answer to one line, or nil for a notification or a line that is not JSON.
    public func handle(line: Data) async -> Data? {
        guard let message = try? JSONValue(json: line), let reply = await handle(message) else { return nil }
        return reply.json
    }

    func handle(_ m: JSONValue) async -> JSONValue? {
        guard let method = m["method"]?.string, let id = m["id"] else { return nil }
        let params = m["params"] ?? .null
        let result: JSONValue
        switch method {
        case "initialize":
            let asked = params["protocolVersion"]?.string ?? ""
            let versions = MCPProtocolInfo.protocolVersions
            result = ["protocolVersion": .string(versions.contains(asked) ? asked : versions[0]),
                      "capabilities": ["tools": [:]],
                      "serverInfo": ["name": .string(name), "version": .string(version)]]
        case "ping":
            result = [:]
        case "tools/list":
            result = ["tools": .array(provider.tools.map { ["name": .string($0.name), "description": .string($0.description), "inputSchema": $0.inputSchema] })]
        case "tools/call":
            let r = await provider.call(params["name"]?.string ?? "", arguments: params["arguments"] ?? [:])
            var content: [JSONValue] = [["type": "text", "text": .string(r.text)]]
            if let png = r.png { content.append(["type": "image", "data": .string(png.base64EncodedString()), "mimeType": "image/png"]) }
            result = ["content": .array(content), "isError": .bool(r.isError)]
        default:
            return ["jsonrpc": "2.0", "id": id, "error": ["code": .int(JSONRPCError.methodNotFound), "message": .string("Unknown method \(method).")]]
        }
        return ["jsonrpc": "2.0", "id": id, "result": result]
    }
}
