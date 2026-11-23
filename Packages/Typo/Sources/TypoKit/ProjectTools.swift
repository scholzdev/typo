import Foundation
import TypstEngine

/// A tool the model may call; the app runs it locally and sends the result back.
public enum ClientTool: String, CaseIterable, Sendable {
    case readFile = "read_file", listFiles = "list_files", searchProject = "search_project"
    case getDiagnostics = "get_diagnostics", getOutline = "get_outline"
    case typstDocs = "typst_docs", viewPreview = "view_preview", compile

    public var summary: String {
        switch self {
        case .readFile: "Returns the current text of one project file (project-relative path). Large files are cut."
        case .listFiles: "Lists the text files of the project, one path per line."
        case .searchProject: "Searches all text files of the project (case-insensitive) and returns file:line: text for each match."
        case .getDiagnostics: "Returns the current compiler errors and warnings of the project."
        case .getOutline: "Returns the headings of one Typst file with their line numbers."
        case .typstDocs: "Searches the bundled Typst reference and returns the best matching functions and syntax with signature, description and example. Use it instead of guessing Typst syntax."
        case .viewPreview: "Renders one page of the compiled document as an image so you can check the layout. Page numbers start at 1; without a page the page shown in the preview is used."
        case .compile: "Waits for the current compile, including your own edits, and returns the compiler errors and warnings."
        }
    }

    /// JSON schema of the arguments.
    public var schema: [String: Any] {
        func object(_ key: String?, _ about: String) -> [String: Any] {
            guard let key else { return ["type": "object", "properties": [String: Any]()] }
            return ["type": "object", "properties": [key: ["type": "string", "description": about]], "required": [key]]
        }
        if self == .viewPreview { return ["type": "object", "properties": ["page": ["type": "integer", "description": "Page number, starting at 1 (optional)"]]] }
        switch self {
        case .readFile: return object("path", "Path relative to the project folder, for example chapters/intro.typ")
        case .getOutline: return object("path", "Path of a .typ file relative to the project folder")
        case .searchProject: return object("query", "The text to search for")
        case .typstDocs: return object("query", "What to look up, for example \"table cell merge\" or \"show rule\"")
        case .listFiles, .getDiagnostics, .compile, .viewPreview: return object(nil, "")
        }
    }
}

/// One tool call of the model; `arguments` is the JSON object as the model wrote it.
public struct ToolCall: Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var arguments: String
    /// Gemini's `thoughtSignature` of the call, which the model wants back with its own turn.
    public var signature: String?
    public init(id: String, name: String, arguments: String, signature: String? = nil) { self.id = id; self.name = name; self.arguments = arguments; self.signature = signature }

    public var input: [String: Any] { (try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any]) ?? [:] }
    public func string(_ key: String) -> String? { input[key] as? String }
    public var tool: ClientTool? { ClientTool(rawValue: name) }
    public var page: Int? { (input["page"] as? Int) ?? (input["page"] as? String).flatMap(Int.init) }
}

public struct ToolResult: Equatable, Sendable {
    public var callID: String
    public var content: String
    public var isError: Bool
    /// A PNG the model should see (`view_preview`); only the current run keeps it, the conversation stores `content`.
    public var image: Data?
    public init(callID: String, content: String, isError: Bool = false, image: Data? = nil) {
        self.callID = callID; self.content = content; self.isError = isError; self.image = image
    }
}

/// What the tools answer, as text; the app supplies the project's data.
public enum ToolOutput {
    public static let fileLimit = 60_000

    public static func file(_ text: String) -> String {
        guard text.count > fileLimit else { return text }
        return String(text.prefix(fileLimit)) + "\n[Cut: \(fileLimit.formatted()) of \(text.count.formatted()) characters shown.]"
    }

    public static func listing(_ paths: [String]) -> String {
        paths.isEmpty ? "The project has no text files." : paths.prefix(500).joined(separator: "\n") + (paths.count > 500 ? "\n[\(paths.count - 500) more not shown]" : "")
    }

    public static func search(_ outcome: SearchOutcome?, limit: Int = 40) -> String {
        guard let outcome else { return "The search was cancelled." }
        if let e = outcome.error { return "The search failed: \(e)" }
        let hits = outcome.files.flatMap(\.hits)
        guard !hits.isEmpty else { return "No matches." }
        let lines = hits.prefix(limit).map { "\($0.file.raw):\($0.line): \($0.context)" }
        return (lines + (hits.count > limit ? ["[\(hits.count - limit) more matches not shown]"] : [])).joined(separator: "\n")
    }

    /// A tool result cut to `limit` characters, which the small on-device window needs.
    public static func capped(_ text: String, limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit)) + "\n[Cut at \(limit) characters.]" : text
    }

    public static let docsLimit = 4_000

    /// The best entries of the bundled Typst reference for `query`, in Markdown, within `limit` characters.
    public static func docs(_ query: String, limit: Int = docsLimit) -> String {
        let found = TypstDocs.search(query)
        guard !found.isEmpty else { return "Nothing in the bundled Typst reference matches “\(query)”. Try another word, or the function's name." }
        var out = "", shown = 0
        for e in found {
            let part = e.text + "\n\n"
            guard out.count + part.count <= limit else { break }
            out += part
            shown += 1
        }
        return shown == 0 ? String(found[0].text.prefix(limit)) : out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func diagnostics(_ problems: [CompilerProblem]) -> String {
        CompilerProblem.list(problems, heading: "Compiler diagnostics:") ?? "No compiler errors or warnings."
    }

    /// Headings (`= Title`) with their lines; a scan of the text, so it works before the first compile.
    public static func outline(_ text: String) -> String {
        var out: [String] = []
        for (i, line) in text.components(separatedBy: "\n").enumerated() {
            let level = line.prefix { $0 == "=" }.count
            guard level > 0, line.dropFirst(level).first == " " else { continue }
            out.append(String(repeating: "  ", count: level - 1) + line.dropFirst(level).trimmingCharacters(in: .whitespaces) + " (line \(i + 1))")
        }
        return out.isEmpty ? "No headings." : out.joined(separator: "\n")
    }
}

/// A compiler error or warning with its place, as the tools report it.
public struct CompilerProblem: Sendable, Equatable {
    public var path: String?
    public var line: Int?
    public var message: String
    public init(path: String?, line: Int?, message: String) { self.path = path; self.line = line; self.message = message }

    /// The problems as a list under `heading`, or nil without any.
    public static func list(_ problems: [CompilerProblem], heading: String) -> String? {
        guard !problems.isEmpty else { return nil }
        return heading + "\n" + problems.map { p in
            let place = [p.path, p.line.map { "line \($0)" }].compactMap { $0 }.joined(separator: ", ")
            return "- " + (place.isEmpty ? "" : place + ": ") + p.message
        }.joined(separator: "\n")
    }

    /// 1-based line of the UTF-16 offset.
    public static func line(of offset: Int, in text: NSString) -> Int {
        var n = 1, i = 0
        let end = min(offset, text.length)
        while i < end {
            let r = text.range(of: "\n", options: .literal, range: NSRange(location: i, length: end - i))
            guard r.location != NSNotFound else { break }
            n += 1; i = NSMaxRange(r)
        }
        return n
    }
}

/// The tools' access to the project, shared by the assistant (after its permission check) and the MCP server.
extension Project {
    /// The longest side of the image `view_preview` returns, in pixels.
    nonisolated public static let previewImageLimit = 1600

    /// The pixels per inch that render a page of `size` points within `limit` pixels on its longer side (at most 144 ppi).
    nonisolated static func previewPPI(pageSize size: CGSize, limit: Int) -> Int {
        let longest = max(size.width, size.height, 1)
        return max(1, min(144, Int((Double(limit) / longest * 72).rounded(.down))))
    }

    /// A project file's text: the open buffer's, else the disk's; nil outside the project.
    public func assistantText(of path: RelPath) -> String? {
        guard allFiles.contains(path) else { return nil }
        return buffer(for: path)?.storage.string ?? (try? String(contentsOf: url(for: path), encoding: .utf8))
    }

    /// The current errors (and warnings unless `errorsOnly`) with file and line.
    public func assistantProblems(errorsOnly: Bool) -> [CompilerProblem] {
        diagnostics.filter { $0.severity == .error || (!errorsOnly && $0.severity == .warning) }.map { d in
            let message = d.severity == .warning ? "warning: " + d.message : d.message
            guard case .project(let loc) = d.origin else { return CompilerProblem(path: nil, line: nil, message: message) }
            let line = assistantText(of: loc.file).map { CompilerProblem.line(of: loc.range.location, in: $0 as NSString) }
            return CompilerProblem(path: loc.file.raw, line: line, message: message)
        }
    }

    /// Runs one of the read-only tools; the caller has checked the permissions. `forAssistant`: the result goes into the
    /// assistant's transcript, which keeps a preview image for one turn only.
    public func runTool(_ call: ToolCall, forAssistant: Bool = true) async -> ToolResult {
        func fail(_ why: String) -> ToolResult { ToolResult(callID: call.id, content: why, isError: true) }
        func ok(_ s: String) -> ToolResult { ToolResult(callID: call.id, content: s) }
        switch call.tool {
        case .readFile?, .getOutline?:
            guard let raw = call.string("path"), let path = RelPath(raw), FileKind.isText(raw), let text = assistantText(of: path) else {
                return fail("\(call.string("path") ?? "That path") is not a text file of this project. Use list_files to see the files.")
            }
            return ok(call.tool == .readFile ? ToolOutput.file(text) : ToolOutput.outline(text))
        case .listFiles?:
            return ok(ToolOutput.listing(allFiles.map(\.raw).filter(FileKind.isText)))
        case .searchProject?:
            guard let query = call.string("query"), !query.isEmpty else { return fail("Give a query.") }
            return ok(ToolOutput.search(await searchForAssistant(query)))
        case .getDiagnostics?:
            return ok(ToolOutput.diagnostics(assistantProblems(errorsOnly: false)))
        case .compile?:
            await settleForAssistant()
            return ok(ToolOutput.diagnostics(assistantProblems(errorsOnly: false)))
        case .typstDocs?:
            guard let query = call.string("query"), !query.isEmpty else { return fail("Give a query.") }
            return ok(ToolOutput.docs(query))
        case .viewPreview?:
            do {
                let shot = try await previewImage(page: call.page)
                return ToolResult(callID: call.id, content: "Page \(shot.page) of \(shot.pageCount) of the preview, as an image." + (forAssistant ? " (Later turns keep only this note.)" : ""),
                                  image: shot.png)
            } catch {
                return fail("The preview could not be rendered: \(error.localizedDescription) Use compile to see the errors.")
            }
        case nil:
            return fail("Unknown tool “\(call.name)”.")
        }
    }

    /// Waits for a compile that covers every edit so far; afterwards `diagnostics` is current.
    public func settleForAssistant() async { _ = await settle() }

    /// A PNG of page `page` (starting at 1; the page shown in the preview when nil), scaled to `limit` pixels on its longer side,
    /// after waiting for the settled compile.
    public func previewImage(page: Int?, limit: Int = previewImageLimit) async throws(ProjectError) -> (png: Data, page: Int, pageCount: Int) {
        let s = try await settledSnapshot()
        let index = (page ?? preview.visiblePage + 1) - 1
        guard s.pages.indices.contains(index) else { throw .exportFailed("The document has \(s.pageCount) page\(s.pageCount == 1 ? "" : "s"); there is no page \(index + 1).") }
        guard let png = await s.png(page: index, ppi: Self.previewPPI(pageSize: s.pages[index].size, limit: limit)) else {
            throw .exportFailed("Page \(index + 1) could not be rendered.")
        }
        return (png, index + 1, s.pageCount)
    }
}
