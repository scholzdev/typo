import Foundation

public enum ProjectError: Error {
    case accessDenied, mainFileMissing(RelPath), unreadable(RelPath), compileFailed([Diagnostic]), exportFailed(String), stale, writeFailed(RelPath, any Error)
    // File management (DESIGN.md section 13). The messages are shown to the user as they are.
    case invalidName(String), nameExists(String), notFound(RelPath), invalidMove(String), operationFailed(String)
}

extension ProjectError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidName(let n): String(localized: "\u{201C}\(n)\u{201D} is not a valid name. A name cannot be empty, contain \u{201C}/\u{201D} or \u{201C}:\u{201D}, or start with a period.", bundle: .module)
        case .nameExists(let n): String(localized: "An item named \u{201C}\(n)\u{201D} already exists in this location.", bundle: .module)
        case .notFound(let p): String(localized: "\u{201C}\(p.raw)\u{201D} no longer exists.", bundle: .module)
        case .invalidMove(let m), .operationFailed(let m): m
        case .writeFailed(let p, let e): String(localized: "\(p.raw) could not be saved: \((e as NSError).localizedDescription)", bundle: .module)
        case .unreadable(let p): String(localized: "\(p.raw) could not be read.", bundle: .module)
        case .mainFileMissing(let p): String(localized: "The main file \(p.raw) is missing.", bundle: .module)
        case .accessDenied: String(localized: "The project folder is not accessible.", bundle: .module)
        case .compileFailed(let d): d.first?.message ?? String(localized: "The document could not be compiled.", bundle: .module)
        case .exportFailed(let m): m
        case .stale: String(localized: "The result is out of date.", bundle: .module)
        }
    }
}
