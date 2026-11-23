import Foundation
import TypoKit
import TypstEngine

/// What the model is told besides the conversation: the system prompt, the attached files, the selection, the errors.
public enum AssistantContext {
    /// Characters of attached file text one request may carry; more is refused, never cut.
    public static let budget = 400_000

    public static let systemPrompt = systemPrompt(proposeEdits: true)

    /// Without `proposeEdits` the model is not told the edit format, so it answers in prose.
    public static func systemPrompt(proposeEdits: Bool, tools: [ClientTool] = []) -> String {
        let head = """
        You are the writing and coding assistant inside Typo, a macOS editor for Typst documents. You help the user with \
        one Typst project: explain Typst markup, scripting and errors, improve the writing\(proposeEdits ? ", and change files on request" : ""). \
        The user may attach project files; they appear below with their paths, and they show the current contents. \
        Answer in the user's language. Use Markdown; put Typst code in ```typst fences.
        """
        let toolNote = !tools.isEmpty ? """


        You can call tools to look at the project: \(tools.map(\.rawValue).joined(separator: ", ")). \
        Use them when the answer depends on files or errors you cannot see, and not for files that are attached already. \
        A tool result shows a file as it is now; read a file before you propose an edit in it, so the SEARCH text matches exactly.\
        \(tools.contains(.typstDocs) ? "\nLook up Typst syntax and function parameters with typst_docs instead of guessing." : "")\
        \(tools.contains(.compile) ? "\nAfter your own edits are applied, call compile to check them." : "")\
        \(tools.contains(.viewPreview) ? "\nCall view_preview to look at the rendered page when the layout matters." : "")
        """ : ""
        guard proposeEdits else {
            return head + toolNote + "\n\nYou cannot change files. Suggest changes in prose or as Typst code in fences, and never write edit blocks."
        }
        return head + toolNote + """


        Answer questions about Typst or the document in prose, with short examples; a question never gets an edit block. \
        Write edit blocks only when the user asks you to change, fix, rewrite or add something in the project, and never \
        claim that a change was accepted or applied.

        To change a file, never print the whole file. Write one or more edit blocks in exactly this format:

        <<<<<<< SEARCH path/to/file.typ
        the exact existing text to replace
        =======
        the replacement text
        >>>>>>> REPLACE

        Rules for edit blocks:
        - The path follows "SEARCH " on the marker line and is relative to the project folder.
        - The SEARCH text must match the file exactly, character for character, including whitespace and indentation, \
        and it must occur exactly once in the file. Include enough surrounding lines to make it unique, but keep it short.
        - To create a new file, leave the SEARCH part empty and use a path that does not exist yet.
        - Several blocks are allowed, also for the same file; each one is applied on its own, in order.
        - The marker lines must stand alone on their lines, exactly as shown.
        Each block is applied to the project, or shown to the user to accept or reject. Explain briefly what each change does.
        """
    }

    public struct File: Sendable, Equatable {
        public var path: String
        public var text: String
        public init(path: String, text: String) { self.path = path; self.text = text }
    }

    /// The attached files as delimited blocks, or nil without files. Throws when they exceed `budget`.
    public static func files(_ files: [File]) throws(AssistantError) -> String? {
        guard !files.isEmpty else { return nil }
        let total = files.reduce(0) { $0 + $1.text.count }
        guard total <= budget else {
            throw .contextTooLarge(characters: total, largest: files.sorted { $0.text.count > $1.text.count }.map(\.path))
        }
        return "Attached project files:\n\n" + files.map { "<file path=\"\($0.path)\">\n\($0.text)\n</file>" }.joined(separator: "\n\n")
    }

    /// The selected text with its file and line range, or nil for an empty selection.
    public static func selection(path: String, in text: String, range: NSRange) -> String? {
        let ns = text as NSString
        guard range.length > 0, NSMaxRange(range) <= ns.length else { return nil }
        let first = line(of: range.location, in: ns), last = line(of: NSMaxRange(range) - 1, in: ns)
        let lines = first == last ? "line \(first)" : "lines \(first)–\(last)"
        return "Selected text (\(path), \(lines)):\n```\n\(ns.substring(with: range))\n```"
    }

    public typealias Problem = CompilerProblem

    /// The compiler errors, or nil without any.
    public static func diagnostics(_ problems: [Problem]) -> String? { CompilerProblem.list(problems, heading: "Compiler errors:") }

    /// 1-based line of the UTF-16 offset.
    public static func line(of offset: Int, in text: NSString) -> Int { CompilerProblem.line(of: offset, in: text) }
}

/// A file change the model proposed in an edit block.
public struct ProposedEdit: Equatable, Sendable {
    public var path: String
    public var search: String
    public var replace: String
    public init(path: String, search: String, replace: String) { self.path = path; self.search = search; self.replace = replace }
}

/// An answer split into prose and edit blocks, in order. Malformed blocks stay prose.
public enum AssistantSegment: Equatable, Sendable {
    case text(String)
    case edit(ProposedEdit)
}

/// How a proposed edit applies to the file as it is now.
public enum EditResolution: Equatable, Sendable {
    /// `before` and `after` are the whole file, for the diff.
    case replace(RelPath, Replacement, before: String, after: String)
    case create(RelPath, String)
    case failed(String)
}

public enum AssistantEdits {
    public static let start = "<<<<<<< SEARCH ", divider = "=======", end = ">>>>>>> REPLACE"

    public static func segments(_ text: String) -> [AssistantSegment] {
        let lines = text.components(separatedBy: "\n")
        var out: [AssistantSegment] = [], prose: [String] = [], inFence = false, i = 0
        func flush() {
            let t = prose.joined(separator: "\n")
            if !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(.text(t)) }
            prose = []
        }
        func trailing(_ s: String) -> String { String(s.reversed().drop { $0.isWhitespace }.reversed()) }
        func isFence(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespaces).hasPrefix("```") }

        while i < lines.count {
            let line = trailing(lines[i])
            if line.hasPrefix(start), case let path = line.dropFirst(start.count).trimmingCharacters(in: .whitespaces), !path.isEmpty,
               let mid = lines[(i + 1)...].firstIndex(where: { trailing($0) == divider || trailing($0).hasPrefix(start) }), trailing(lines[mid]) == divider,
               let stop = lines[(mid + 1)...].firstIndex(where: { trailing($0) == end || trailing($0).hasPrefix(start) }), trailing(lines[stop]) == end {
                // An odd number of fences before the block: the last one opens a fence around it, which is dropped with its closer.
                if prose.count(where: isFence) % 2 == 1, let f = prose.lastIndex(where: isFence), prose[(f + 1)...].allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    prose.removeSubrange(f...)
                    inFence = true
                }
                flush()
                out.append(.edit(ProposedEdit(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "`\"'")),
                                              search: lines[(i + 1)..<mid].joined(separator: "\n"),
                                              replace: lines[(mid + 1)..<stop].joined(separator: "\n"))))
                i = stop + 1
                continue
            }
            if inFence, line.trimmingCharacters(in: .whitespaces) == "```" {
                inFence = false
            } else if !(inFence && line.trimmingCharacters(in: .whitespaces).isEmpty) {
                prose.append(lines[i])
            }
            i += 1
        }
        flush()
        return out
    }

    public static func parse(_ text: String) -> [ProposedEdit] {
        segments(text).compactMap { if case .edit(let e) = $0 { e } else { nil } }
    }

    /// Resolves `edit` against the file's current text; nil `text` means the project has no such file.
    public static func resolve(_ edit: ProposedEdit, text: String?) -> EditResolution {
        guard let path = RelPath(edit.path) else { return .failed("“\(edit.path)” is not a path inside the project.") }
        guard FileKind.isText(path.raw) else { return .failed("\(path.raw) is not a text file.") }
        guard let text else {
            return edit.search.isEmpty ? .create(path, edit.replace) : .failed("\(path.raw) does not exist in the project.")
        }
        let ns = text as NSString
        if edit.search.isEmpty {
            guard ns.length == 0 else { return .failed("\(path.raw) already exists, so it cannot be created.") }
            return .replace(path, Replacement(range: NSRange(location: 0, length: 0), text: edit.replace), before: text, after: edit.replace)
        }
        var matches: [NSRange] = [], from = 0
        while from < ns.length {
            let r = ns.range(of: edit.search, options: .literal, range: NSRange(location: from, length: ns.length - from))
            guard r.location != NSNotFound else { break }
            matches.append(r)
            from = r.location + 1    // one step, so overlapping matches count too
        }
        guard let r = matches.first else { return .failed("The text to replace was not found in \(path.raw). The file may have changed since the answer.") }
        guard matches.count == 1 else { return .failed("The text to replace occurs \(matches.count) times in \(path.raw), so the change is ambiguous.") }
        return .replace(path, Replacement(range: r, text: edit.replace), before: text, after: ns.replacingCharacters(in: r, with: edit.replace))
    }
}
