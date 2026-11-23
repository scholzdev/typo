import Foundation

public enum ProjectError: Error {
    case accessDenied, mainFileMissing(RelPath), unreadable(RelPath), compileFailed([Diagnostic]), exportFailed(String), stale, writeFailed(RelPath, any Error)
    // File management (DESIGN.md section 13). The messages are shown to the user as they are.
    case invalidName(String), nameExists(String), notFound(RelPath), invalidMove(String), operationFailed(String)
}

extension ProjectError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidName(let n): "\u{201C}\(n)\u{201D} is not a valid name. A name cannot be empty, contain \u{201C}/\u{201D} or \u{201C}:\u{201D}, or start with a period."
        case .nameExists(let n): "An item named \u{201C}\(n)\u{201D} already exists in this location."
        case .notFound(let p): "\u{201C}\(p.raw)\u{201D} no longer exists."
        case .invalidMove(let m), .operationFailed(let m): m
        case .writeFailed(let p, let e): "\(p.raw) could not be saved: \((e as NSError).localizedDescription)"
        case .unreadable(let p): "\(p.raw) could not be read."
        case .mainFileMissing(let p): "The main file \(p.raw) is missing."
        case .accessDenied: "The project folder is not accessible."
        case .compileFailed(let d): d.first?.message ?? "The document could not be compiled."
        case .exportFailed(let m): m
        case .stale: "The result is out of date."
        }
    }
}
