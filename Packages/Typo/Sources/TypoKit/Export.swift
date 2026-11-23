import Foundation

public enum PageFormat: Sendable, Equatable {
    case png(ppi: Int)
    case svg
}

struct ArchiveError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension Project {
    /// Zips the project folder without hidden files and folders (.git, .DS_Store); unsaved buffers are written first.
    public func exportArchive(to url: URL) async throws {
        try await saveAll()
        let root = rootURL
        try await Task.detached {
            try? FileManager.default.removeItem(at: url)   // zip would add to an existing archive
            let p = Process(), err = Pipe()
            p.executableURL = URL(filePath: "/usr/bin/zip")
            p.arguments = ["-r", "-q", url.path, ".", "-x", ".*", "-x", "*/.*"]
            p.currentDirectoryURL = root
            p.standardError = err
            try p.run()
            let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                throw ArchiveError(message: msg.isEmpty ? "zip failed (exit \(p.terminationStatus))." : msg)
            }
        }.value
    }
}
