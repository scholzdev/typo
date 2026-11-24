import Foundation
import TypstEngine

public struct PackageTemplate: Sendable, Hashable, Identifiable, Decodable {
    public var id: String { name }
    public let name: String
    public let version: String
    public let description: String
    public let authors: [String]
    public let categories: [String]
    public let path: String        // template directory inside the package
    public let entrypoint: String  // main file, relative to the template directory
    public var spec: String { "@preview/\(name):\(version)" }
    /// Universe's small page preview (webp).
    public var thumbnailURL: URL { URL(string: "https://packages.typst.org/preview/thumbnails/\(name)-\(version)-small.webp")! }
}

public enum TemplateError: LocalizedError, Equatable {
    case destinationExists(String)   // folder name
    case fetchFailed(String)         // bridge error text
    case invalidTemplate(String)     // template dir or entrypoint missing in the package

    public var errorDescription: String? {
        switch self {
        case .destinationExists(let n): String(localized: "A folder named \"\(n)\" already exists.", bundle: .module)
        case .fetchFailed(let m): String(localized: "Could not get the template package: \(m)", bundle: .module)
        case .invalidTemplate(let m): String(localized: "The template package is invalid: \(m)", bundle: .module)
        }
    }
}

extension TypstRuntime {
    /// Universe templates, one per name at its latest compatible version, sorted by name. Uses the cached index;
    /// when none has been applied yet (first launch) it awaits one revalidation first. Empty when that fails too.
    public func templates() async -> [PackageTemplate] {
        func decode() -> [PackageTemplate] {
            (try? JSONDecoder().decode([PackageTemplate].self, from: Bridge.templates(handle))) ?? []
        }
        let cached = decode()
        if !cached.isEmpty { return cached }
        await packageIndex.revalidate()
        return decode()
    }

    /// `typst init`: fetches the package (local packages, cache, then Universe), creates `folder` and copies the
    /// contents of the package's template directory into it. Returns the main file. `folder` must not exist:
    /// an existing path throws `.destinationExists` and is left untouched (NSSavePanel's "Replace" must never merge or delete).
    public func createProject(from template: PackageTemplate, at folder: URL) async throws(TemplateError) -> RelPath {
        let result = await Task.detached(priority: .userInitiated) { [self] in
            Result { () throws(TemplateError) -> RelPath in try copyTemplate(template, to: folder) }
        }.value
        return try result.get()
    }

    private func copyTemplate(_ t: PackageTemplate, to folder: URL) throws(TemplateError) -> RelPath {
        let fm = FileManager.default
        // attributesOfItem also sees dangling symlinks, which fileExists does not.
        if fm.fileExists(atPath: folder.path) || (try? fm.attributesOfItem(atPath: folder.path)) != nil {
            throw .destinationExists(folder.lastPathComponent)
        }
        let fetched = Bridge.fetchPackage(handle, spec: t.spec)
        guard fetched.ok else { throw .fetchFailed(fetched.text) }
        let root = URL(fileURLWithPath: fetched.text).standardizedFileURL
        let dir = root.appending(path: t.path).standardizedFileURL
        let main = dir.appending(path: t.entrypoint).standardizedFileURL
        var isDir: ObjCBool = false
        guard let entry = RelPath(t.entrypoint),
              (dir.path + "/").hasPrefix(root.path + "/"), fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue,
              main.path.hasPrefix(dir.path + "/"), fm.fileExists(atPath: main.path) else {
            throw .invalidTemplate("missing \(t.path)/\(t.entrypoint)")
        }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: false)
            for child in try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                try fm.copyItem(at: child, to: folder.appending(path: child.lastPathComponent))
            }
        } catch {
            try? fm.removeItem(at: folder)   // we created it just above
            throw .invalidTemplate(error.localizedDescription)
        }
        return entry
    }
}
