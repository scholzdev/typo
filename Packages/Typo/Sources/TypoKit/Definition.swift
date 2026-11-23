import Foundation
import TypstEngine

/// A function or type of Typst itself with its documentation (Markdown) and typst.app page, if known.
public struct BuiltinDoc: Sendable, Equatable {
    public let name: String
    public let docs: String
    public let url: URL?

    public init(name: String, docs: String, url: URL?) { self.name = name; self.docs = docs; self.url = url }
}

/// Where the item under the caret is defined, as the Typst compiler resolves it (imports, packages and the standard library included).
public enum DefinitionTarget: Sendable, Equatable {
    case source(RelPath, NSRange)
    case file(RelPath)
    /// A function, type or constant of Typst itself.
    case builtin(BuiltinDoc)
    /// Somewhere inside a package: `@preview/name:1.0.0/path.typ`.
    case package(String)
}

extension Project {
    /// The definition of the identifier, import path or label at `offset` (UTF-16) of the current text of `file`.
    /// Nil when there is none, a newer request superseded this one, or the engine could not answer.
    public func definition(in file: RelPath, at offset: Int) async -> DefinitionTarget? {
        let answer = await ask { reply in .definition(DefinitionRequest(file: file, cursor: offset, reply: reply)) }
        defer { trimLog() }
        guard let a = answer, let d = a.definition else { return nil }
        switch d.kind {
        case .std: return .builtin(BuiltinDoc(name: d.name, docs: d.docs, url: URL(string: d.url)))
        case .package: return .package("\(d.name)/\(d.path)")
        case .file: return RelPath(d.path).map { .file($0) }
        case .span:
            guard let rel = RelPath(d.path), let r = log.map(d.range, in: rel, from: a.seq) else { return nil }
            return .source(rel, r)
        }
    }
}

extension Project {
    /// The function at `offset` written out with every parameter and the types it accepts
    /// (`figure(\n  body: content,\n  alt: none | str,\n …)`), for Quick Help. Built-ins and the project's own functions.
    public func signature(in file: RelPath, at offset: Int) async -> String? {
        let answer = await ask { reply in .definition(DefinitionRequest(file: file, cursor: offset, reply: reply)) }
        defer { trimLog() }
        guard let s = answer?.definition?.signature, !s.isEmpty else { return nil }
        return s
    }
}
