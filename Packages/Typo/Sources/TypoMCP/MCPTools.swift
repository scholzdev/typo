import Foundation
import JSONRPC
import MCPProtocol
import TypoKit
import TypstEngine

/// Typo's Typst tools for any AI agent, served by `MCPServer` in `typo-mcp`. Read-only; the project opens at the
/// first call that needs it.
@MainActor public final class TypoMCPTools: MCPToolProvider {
    /// The tools only MCP offers: the assistant has the app's own panels for these.
    enum Extra: String, CaseIterable {
        case listPackages = "list_packages", listFonts = "list_fonts"
        var summary: String {
            switch self {
            case .listPackages: "Lists the Typst packages available offline: the downloaded @preview packages and the local packages folder, as @namespace/name:version."
            case .listFonts: "Lists the font families the Typst compiler can use for this project (system fonts, the fonts Typst ships and the project's own font files)."
            }
        }
    }

    private let root: URL?
    private let localPackages: URL?
    private let runtime: () async -> TypstRuntime
    private var project: Project?

    /// `root`: the project folder (see `projectRoot(from:)`); nil leaves only the tools that need no project.
    public convenience init(root: URL?, localPackages: URL?) {
        self.init(root: root, localPackages: localPackages) { await TypstRuntime.shared.value }
    }

    init(root: URL?, localPackages: URL? = nil, runtime: @escaping () async -> TypstRuntime) {
        self.root = root; self.localPackages = localPackages; self.runtime = runtime
    }

    public var tools: [MCPTool] {
        ClientTool.allCases.map { MCPTool(name: $0.rawValue, description: $0.summary, inputSchema: JSONValue(any: $0.schema)) }
            + Extra.allCases.map { MCPTool(name: $0.rawValue, description: $0.summary, inputSchema: ["type": "object", "properties": [:]]) }
    }

    public func call(_ name: String, arguments: JSONValue) async -> MCPToolResult {
        let r = await call(ToolCall(id: "mcp", name: name, arguments: String(decoding: arguments.json, as: UTF8.self)))
        return MCPToolResult(text: r.content, png: r.image, isError: r.isError)
    }

    private func call(_ call: ToolCall) async -> ToolResult {
        func fail(_ why: String) -> ToolResult { ToolResult(callID: call.id, content: why, isError: true) }
        if call.tool == .typstDocs {
            guard let query = call.string("query"), !query.isEmpty else { return fail("Give a query.") }
            return ToolResult(callID: call.id, content: ToolOutput.docs(query))
        }
        guard call.tool != nil || Extra(rawValue: call.name) != nil else { return fail("Unknown tool “\(call.name)”.") }
        if call.name == Extra.listPackages.rawValue { return ToolResult(callID: call.id, content: packages()) }
        let project: Project
        do { project = try await openProject() } catch { return fail(error.localizedDescription) }
        // No file watcher here: the agent may have changed files since the last call.
        await project.refreshFiles()
        if call.name == Extra.listFonts.rawValue {
            let names = await project.fontFamilyNames(host: project.main).filter { !$0.hasPrefix(".") }
            return ToolResult(callID: call.id, content: names.isEmpty ? "The compiler lists no fonts." : names.joined(separator: "\n"))
        }
        if [.getDiagnostics, .compile, .viewPreview].contains(call.tool) {
            project.engine.send(.recompile)    // a changed file that is not open reaches the compiler only with a new compile
            await project.settleForAssistant()
        }
        return await project.runTool(call, forAssistant: false)
    }

    private func openProject() async throws -> Project {
        if let project { return project }
        guard let root else { throw ProjectError.operationFailed("No Typst project here. Start typo-mcp with --project <folder>, or in the project's folder.") }
        guard let main = Self.mainFile(in: root) else { throw ProjectError.operationFailed("\(root.path) has no .typ file.") }
        let rt = await runtime()
        if let localPackages { rt.setPackagesDir(localPackages) }
        let p = try await Project(id: ProjectID(), root: root, main: main, runtime: rt)
        p.autosaveDelay = nil
        project = p
        return p
    }

    private func packages() -> String {
        let found = InstalledPackage.list(in: TypstRuntime.packageDirectory, measured: false)
            + (localPackages.map { InstalledPackage.list(in: $0, measured: false) } ?? [])
        return found.isEmpty ? "No packages are downloaded or installed locally." : found.map { "@\($0.id)" }.joined(separator: "\n")
    }

    // MARK: Project

    /// `dir` if it holds a .typ file, else the nearest folder above it with a typst.toml or a .typ file.
    nonisolated public static func projectRoot(from dir: URL) -> URL? {
        let fm = FileManager.default
        var d = dir.standardizedFileURL
        func typs(_ d: URL) -> Bool { ((try? fm.contentsOfDirectory(atPath: d.path)) ?? []).contains { $0.hasSuffix(".typ") } }
        while true {
            if typs(d) || fm.fileExists(atPath: d.appending(path: "typst.toml").path) { return d }
            let up = d.deletingLastPathComponent()
            if up.path == d.path { return nil }
            d = up
        }
    }

    /// The typst.toml's entrypoint when that file exists, else main.typ, else the first .typ file (as the app opens a folder).
    nonisolated public static func mainFile(in root: URL) -> RelPath? {
        let fm = FileManager.default
        if let toml = try? String(contentsOf: root.appending(path: "typst.toml"), encoding: .utf8),
           let m = toml.firstMatch(of: /(?m)^\s*entrypoint\s*=\s*"([^"]+)"/), let p = RelPath(String(m.1)),
           fm.fileExists(atPath: root.appending(path: p.raw).path) { return p }
        let typs = ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).filter { $0.hasSuffix(".typ") }.sorted()
        return (typs.contains("main.typ") ? "main.typ" : typs.first).flatMap(RelPath.init)
    }
}
