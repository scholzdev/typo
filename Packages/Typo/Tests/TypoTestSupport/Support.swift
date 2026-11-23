import Foundation
import PDFKit
@testable import TypoKit
@testable import TypstEngine
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

public enum TestEnv {
    public static var fixtures: URL { Bundle.module.resourceURL!.appending(path: "Fixtures") }

    /// One runtime for the whole run, with its own package cache so the @preview download really happens.
    public static let runtime: Task<TypstRuntime, Never> = Task {
        let base = FileManager.default.temporaryDirectory.appending(path: "typstcore-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return await TypstRuntime.load(indexURL: base.appending(path: "font-index.json"), packageDir: base.appending(path: "packages"),
                                       packageFetch: { _ in throw URLError(.notConnectedToInternet) })   // no real network in tests
    }

    /// Copies a fixture folder to a fresh temp dir so tests may write.
    public static func copyFixture(_ name: String) throws -> URL {
        let src = TestEnv.fixtures.appending(path: "\(name)")
        let dst = FileManager.default.temporaryDirectory.appending(path: "typstcore-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: src, to: dst)
        return dst
    }

    @MainActor public static func project(_ fixture: String, main: String = "main.typ") async throws -> (Project, URL) {
        let root = try copyFixture(fixture)
        let p = try await Project(id: ProjectID(), root: root, main: RelPath(main)!, runtime: await runtime.value)
        p.autosaveDelay = nil
        return (p, root)
    }

    public static func pdfText(_ data: Data) -> String {
        let doc = PDFDocument(data: data)!
        return (0..<doc.pageCount).map { doc.page(at: $0)?.string ?? "" }.joined(separator: "\n")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// Edits go through the storage like a text view does, registering the inverse with the buffer's UndoManager.
@MainActor public func replace(_ b: Buffer, _ range: NSRange, with s: String) {
    let old = (b.storage.string as NSString).substring(with: range)
    b.storage.replaceCharacters(in: range, with: s)
    let um = b.undoManager
    let own = um.groupingLevel == 0 && !um.isUndoing && !um.isRedoing   // groupsByEvent is off: no run loop here
    if own { um.beginUndoGrouping() }
    um.registerUndo(withTarget: b) { b in
        MainActor.assumeIsolated { replace(b, NSRange(location: range.location, length: (s as NSString).length), with: old) }
    }
    if own { um.endUndoGrouping() }
}

@MainActor public func type(_ b: Buffer, _ s: String, at loc: Int? = nil) {
    var at = loc ?? b.storage.length
    for ch in s {
        replace(b, NSRange(location: at, length: 0), with: String(ch))
        at += String(ch).utf16.count
    }
}

extension TestEnv {
    @MainActor public static func project(files: [String: String], main: String = "main.typ", runtime: TypstRuntime? = nil) async throws -> (Project, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "typstcore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (name, text) in files {
            let url = root.appending(path: name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        let rt = if let runtime { runtime } else { await Self.runtime.value }
        let p = try await Project(id: ProjectID(), root: root, main: RelPath(main)!, runtime: rt)
        p.autosaveDelay = nil
        return (p, root)
    }

    /// A runtime whose package cache is seeded with `indexJSON` (fresh, so nothing is fetched).
    public static func runtime(packageIndex indexJSON: Data) async throws -> TypstRuntime {
        let base = FileManager.default.temporaryDirectory.appending(path: "typstcore-tests-\(UUID().uuidString)")
        let dir = base.appending(path: "packages/preview")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try indexJSON.write(to: dir.appending(path: "index.json"))
        return await TypstRuntime.load(indexURL: base.appending(path: "font-index.json"), packageDir: base.appending(path: "packages"),
                                       packageFetch: { _ in throw URLError(.notConnectedToInternet) })
    }
}
