import CoreGraphics
import Foundation

public enum CompileStatus: Sendable, Equatable { case idle, compiling, downloading(package: String) }

public struct Location: Hashable, Sendable {
    public let file: RelPath
    public let range: NSRange
    public init(file: RelPath, range: NSRange) { self.file = file; self.range = range }
}

public struct Diagnostic: Identifiable, Sendable {
    /// `hint`: a lint hint (Lint.swift), never from the compiler.
    public enum Severity: Sendable { case error, warning, hint }
    public enum Origin: Sendable { case project(Location), package(String), detached }
    public let id: Int
    public let severity: Severity
    public let message: String
    public let hints: [String]
    public let origin: Origin

    public init(id: Int, severity: Severity, message: String, hints: [String], origin: Origin) {
        self.id = id; self.severity = severity; self.message = message; self.hints = hints; self.origin = origin
    }

    public func with(range: NSRange) -> Diagnostic {
        guard case .project(let loc) = origin else { return self }
        return Diagnostic(id: id, severity: severity, message: message, hints: hints,
                          origin: .project(Location(file: loc.file, range: range)))
    }
}

/// Everything one compile produced, stamped with the last edit it saw.
public struct CompileResult: Sendable {
    public let seq: Seq                          // covers every edit <= seq, in every file
    public let snapshot: Snapshot
    public let main: RelPath                     // the document this compile was of
    public let serial: Int                       // engine compile number: orders results of equal seq, e.g. across a main switch
}

public struct PageInfo: Identifiable, Sendable {
    public let id: Int                    // page index
    public let hash: UInt128              // content identity; equal hash = identical pixels
    public let size: CGSize               // points
    public let snapshot: Snapshot
}
