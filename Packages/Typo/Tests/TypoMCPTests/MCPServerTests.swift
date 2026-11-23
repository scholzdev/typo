import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import JSONRPC
@testable import MCPProtocol
@testable import TypoMCP

@MainActor private func server(_ files: [String: String]) async throws -> (MCPServer, URL) {
    let root = FileManager.default.temporaryDirectory.appending(path: "typstcore-mcp-\(UUID().uuidString)")
    for (name, text) in files {
        let url = root.appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
    return (MCPServer(name: "typo", version: "test", tools: TypoMCPTools(root: TypoMCPTools.projectRoot(from: root)) { await TestEnv.runtime.value }), root)
}

@MainActor private func send(_ s: MCPServer, _ line: String) async throws -> JSONValue? {
    try await s.handle(line: Data(line.utf8)).map { try JSONValue(json: $0) }
}

@MainActor private func call(_ s: MCPServer, _ tool: String, _ arguments: String = "{}") async throws -> JSONValue {
    try #require(try await send(s, #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"\#(tool)","arguments":\#(arguments)}}"#)?["result"])
}

private func text(_ result: JSONValue) -> String { result["content"]?.array?.first?["text"]?.string ?? "" }

@MainActor @Suite(.timeLimit(.minutes(2))) struct MCPServerTests {
    @Test func initializeAgreesOnAVersionItSpeaks() async throws {
        let (s, _) = try await server(["main.typ": "Hi"])
        let old = try #require(try await send(s, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}"#))
        #expect(old["id"] == 1 && old["result"]?["protocolVersion"] == "2024-11-05")
        #expect(old["result"]?["serverInfo"]?["name"] == "typo" && old["result"]?["capabilities"]?["tools"] == [:])
        let future = try #require(try await send(s, #"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"2099-01-01"}}"#))
        #expect(future["id"] == "a" && future["result"]?["protocolVersion"] == "2025-06-18")
    }

    @Test func notificationsMalformedLinesAndUnknownMethods() async throws {
        let (s, _) = try await server(["main.typ": "Hi"])
        #expect(try await send(s, #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
        #expect(try await send(s, "{not json") == nil)
        #expect(try await send(s, #"{"jsonrpc":"2.0","id":2,"method":"ping"}"#)?["result"] == [:])
        let unknown = try #require(try await send(s, #"{"jsonrpc":"2.0","id":3,"method":"resources/list"}"#))
        #expect(unknown["error"]?["code"]?.int == -32601 && unknown["result"] == nil)
    }

    @Test func listsEveryToolWithItsSchema() async throws {
        let (s, _) = try await server(["main.typ": "Hi"])
        let tools = try #require(try await send(s, #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)?["result"]?["tools"]?.array)
        let names = tools.compactMap { $0["name"]?.string }
        #expect(Set(names) == Set(ClientTool.allCases.map(\.rawValue) + ["list_packages", "list_fonts"]) && names.count == tools.count)
        #expect(tools.allSatisfy { $0["inputSchema"]?["type"] == "object" && $0["description"]?.string?.isEmpty == false })
        #expect(tools.first { $0["name"] == "read_file" }?["inputSchema"]?["required"] == ["path"])
    }

    @Test func compileFollowsEditsOnDisk() async throws {
        let (s, root) = try await server(["main.typ": "= Intro\n#include \"ch.typ\"\n", "ch.typ": "== Part\nok"])
        #expect(text(try await call(s, "compile")) == "No compiler errors or warnings.")
        #expect(text(try await call(s, "get_outline", #"{"path":"main.typ"}"#)).contains("Intro (line 1)"))
        // An agent changes both files behind the server's back.
        try "= Intro\n#include \"ch.typ\"\n#nope\n".write(to: root.appending(path: "main.typ"), atomically: true, encoding: .utf8)
        try "== Part\n#alsonope".write(to: root.appending(path: "ch.typ"), atomically: true, encoding: .utf8)
        let diagnostics = text(try await call(s, "get_diagnostics"))
        #expect(diagnostics.contains("nope") && diagnostics.contains("alsonope"))
        #expect(text(try await call(s, "read_file", #"{"path":"main.typ"}"#)).contains("#nope"))
    }

    @Test func docsFontsPackagesAndPreview() async throws {
        let (s, root) = try await server(["main.typ": "Hello"])
        #expect(text(try await call(s, "typst_docs", #"{"query":"table"}"#)).contains("table"))
        #expect(text(try await call(s, "list_fonts")).contains("New Computer Modern"))
        try FileManager.default.copyItem(at: TestEnv.fixtures.appending(path: "fonts/Geist-Regular.ttf"), to: root.appending(path: "Geist.ttf"))
        #expect(text(try await call(s, "list_fonts")).split(separator: "\n").contains("Geist"))
        #expect(try await call(s, "list_packages")["isError"] == false)
        let preview = try await call(s, "view_preview")
        #expect(text(preview) == "Page 1 of 1 of the preview, as an image.")
        let image = try #require(preview["content"]?.array?.first { $0["type"] == "image" })
        #expect(image["mimeType"] == "image/png" && Data(base64Encoded: image["data"]?.string ?? "")?.starts(with: [0x89, 0x50, 0x4E, 0x47]) == true)
    }

    @Test func toolErrorsAreResultsNotProtocolErrors() async throws {
        let (s, _) = try await server(["main.typ": "Hi"])
        let missing = try await call(s, "read_file", #"{"path":"nope.typ"}"#)
        #expect(missing["isError"] == true && text(missing).contains("not a text file"))
        #expect(try await call(s, "rm_rf")["isError"] == true)
        let nowhere = MCPServer(name: "typo", version: "test", tools: TypoMCPTools(root: nil) { await TestEnv.runtime.value })
        let r = try #require(try await send(nowhere, #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_diagnostics"}}"#)?["result"])
        #expect(r["isError"] == true && text(r).contains("--project"))
        #expect(try await call(nowhere, "typst_docs", #"{"query":"heading"}"#)["isError"] == false)
    }

    @Test func projectRootAndMainFile() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(path: "typstcore-mcp-root-\(UUID().uuidString)")
        let deep = base.appending(path: "pkg/src/deep")
        try fm.createDirectory(at: deep, withIntermediateDirectories: true)
        try "[package]\nentrypoint = \"src/lib.typ\"\n".write(to: base.appending(path: "pkg/typst.toml"), atomically: true, encoding: .utf8)
        try "".write(to: base.appending(path: "pkg/src/lib.typ"), atomically: true, encoding: .utf8)
        #expect(TypoMCPTools.projectRoot(from: deep)?.path == base.appending(path: "pkg/src").standardizedFileURL.path)
        try fm.removeItem(at: base.appending(path: "pkg/src/lib.typ"))
        #expect(TypoMCPTools.projectRoot(from: deep)?.path == base.appending(path: "pkg").standardizedFileURL.path)
        try "".write(to: base.appending(path: "pkg/src/lib.typ"), atomically: true, encoding: .utf8)
        #expect(TypoMCPTools.mainFile(in: base.appending(path: "pkg"))?.raw == "src/lib.typ")
        for f in ["b.typ", "a.typ"] { try "".write(to: deep.appending(path: f), atomically: true, encoding: .utf8) }
        #expect(TypoMCPTools.mainFile(in: deep)?.raw == "a.typ")
        try "".write(to: deep.appending(path: "main.typ"), atomically: true, encoding: .utf8)
        #expect(TypoMCPTools.mainFile(in: deep)?.raw == "main.typ")
    }

    @Test func desktopConfigKeepsOtherSettingsAndRefusesBadJSON() throws {
        let merged = try #require(MCPInstall.merging(Data(#"{"theme":"dark","mcpServers":{"other":{"command":"x"}}}"#.utf8), command: "/A/typo-mcp"))
        let o = try JSONValue(json: merged)
        #expect(o["theme"] == "dark" && o["mcpServers"]?["other"]?["command"] == "x")
        #expect(o["mcpServers"]?["typo"] == ["command": "/A/typo-mcp", "args": []] && MCPInstall.isAdded(merged))
        #expect(String(decoding: merged, as: UTF8.self).contains("/A/typo-mcp"))
        #expect(MCPInstall.merging(Data("{oops".utf8), command: "/x") == nil && MCPInstall.merging(Data("[1]".utf8), command: "/x") == nil)
        #expect(MCPInstall.isAdded(MCPInstall.merging(nil, command: "/x")) && !MCPInstall.isAdded(Data("{}".utf8)))

        let dir = FileManager.default.temporaryDirectory.appending(path: "typstcore-claude-\(UUID().uuidString)")
        let url = dir.appending(path: "claude_desktop_config.json")
        #expect(MCPInstall.addToDesktop(command: "/x", config: url).ok)
        #expect(MCPInstall.addToDesktop(command: "/y", config: url).ok)
        #expect(MCPInstall.isAdded(try Data(contentsOf: url.appendingPathExtension("bak"))))
        try Data("{bad".utf8).write(to: url)
        #expect(!MCPInstall.addToDesktop(command: "/x", config: url).ok)
        #expect(try Data(contentsOf: url) == Data("{bad".utf8))
    }
}

/// The assistant runs its tools through `Project.runTool` after its permission check; this is the same path.
@MainActor @Suite struct SharedToolRunnerTests {
    @Test func readsListsSearchesAndOutlines() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= Title\nfigure here", "notes.txt": "x"])
        func run(_ name: String, _ args: String = "{}") async -> ToolResult { await p.runTool(ToolCall(id: "c", name: name, arguments: args)) }
        #expect(await run("read_file", #"{"path":"main.typ"}"#).content == "= Title\nfigure here")
        #expect(await run("list_files").content.contains("notes.txt"))
        #expect(await run("search_project", #"{"query":"figure"}"#).content == "main.typ:2: figure here")
        #expect(await run("get_outline", #"{"path":"main.typ"}"#).content == "Title (line 1)")
        await p.settleForAssistant()
        #expect(await run("view_preview").content == "Page 1 of 1 of the preview, as an image. (Later turns keep only this note.)")
        #expect(await run("search_project").isError)
        #expect(await run("nope").isError)
    }
}
