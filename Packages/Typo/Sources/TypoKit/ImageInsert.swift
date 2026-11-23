import Foundation
import TypstEngine

/// Images dropped or pasted into the editor: where they go in the project and the code that shows them.
public enum ImageInsert {
    public static let folder = "images"

    /// The project's own images folder (first of these that `isFolder` finds), else `images`.
    public static func folder(isFolder: (String) -> Bool) -> String {
        ["images", "assets", "img", "figures"].first(where: isFolder) ?? folder
    }

    /// A dropped file's name in kebab-case ("My Photo (1).PNG" -> "my-photo-1.png").
    public static func kebabName(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        var stem = ""
        for ch in (name as NSString).deletingPathExtension.lowercased() {
            if ch.isLetter || ch.isNumber { stem.append(ch) } else if !stem.hasSuffix("-") { stem.append("-") }
        }
        stem = stem.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if stem.isEmpty { stem = "image" }
        return ext.isEmpty ? stem : "\(stem).\(ext)"
    }

    public static func isImage(_ path: String) -> Bool {
        ["png", "jpg", "jpeg", "gif", "svg", "webp", "pdf"].contains((path as NSString).pathExtension.lowercased())
    }

    /// `name`, else "stem-2.ext", "stem-3.ext", ...: the first one `taken` does not claim.
    public static func uniqueName(_ name: String, taken: (String) -> Bool) -> String {
        let ext = (name as NSString).pathExtension, stem = (name as NSString).deletingPathExtension
        var candidate = name, i = 2
        while taken(candidate) {
            candidate = ext.isEmpty ? "\(stem)-\(i)" : "\(stem)-\(i).\(ext)"
            i += 1
        }
        return candidate
    }

    /// "screenshot-yyyyMMdd-HHmmss.png" in `timeZone`.
    public static func pastedName(at date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyyMMdd-HHmmss"
        return "screenshot-\(f.string(from: date)).png"
    }

    /// `target` as Typst resolves it from inside `file`: relative to the file's folder.
    public static func relativePath(from file: RelPath, to target: RelPath) -> String {
        let dir = file.parent.map { $0.raw.split(separator: "/") } ?? []
        let parts = target.raw.split(separator: "/")
        var common = 0
        while common < dir.count, common < parts.count - 1, dir[common] == parts[common] { common += 1 }
        return (Array(repeating: "..", count: dir.count - common) + parts[common...].map(String.init)).joined(separator: "/")
    }

    /// A label body from a file stem: lowercased, runs of anything Typst labels do not allow become "-".
    public static func label(for stem: String) -> String {
        var out = ""
        for ch in stem.lowercased() {
            if ch.isLetter || ch.isNumber || "_-.:".contains(ch) { out.append(ch) } else if !out.hasSuffix("-") { out.append("-") }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return trimmed.isEmpty ? "image" : trimmed
    }

    /// `fig:<stem>` for each path, made unique against `taken` and against each other (-2, -3, ...).
    public static func figureLabels(_ paths: [String], taken: (String) -> Bool) -> [String] {
        var used = Set<String>()
        return paths.map { p in
            let base = "fig:" + label(for: ((p as NSString).lastPathComponent as NSString).deletingPathExtension)
            let name = uniqueName(base) { taken($0) || used.contains($0) }
            used.insert(name)
            return name
        }
    }

    /// The code for `paths` (already relative to the edited file) in `mode`. Markup gets one figure per image; Tab
    /// goes caption, then alt text; code gets `image("…")`; a string or raw text gets the bare path.
    public static func snippet(_ paths: [String], mode: SyntaxMode, labelTaken: (String) -> Bool = { _ in false }) -> Snippet {
        let quoted = { (p: String) in "\"" + p.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        switch mode {
        case .markup:
            var text = "", stops: [NSRange] = [], groups: [Int] = []
            for (i, (p, label)) in zip(paths, figureLabels(paths, taken: labelTaken)).enumerated() {
                if !text.isEmpty { text += "\n\n" }
                text += "#figure(\n  image(\(quoted(p)), alt: \""
                stops.append(NSRange(location: text.utf16.count, length: 0)); groups.append(2 * i + 2)
                text += "\"),\n  caption: ["
                stops.append(NSRange(location: text.utf16.count, length: 0)); groups.append(2 * i + 1)
                text += "],\n) <\(label)>"
            }
            return Snippet(text: text, placeholders: stops, groups: groups)
        case .code: return Snippet(text: paths.map { "image(\(quoted($0)))" }.joined(separator: ", "), placeholders: [])
        case .math: return Snippet(text: paths.map { "#image(\(quoted($0)))" }.joined(separator: " "), placeholders: [])
        case .text: return Snippet(text: paths.joined(separator: " "), placeholders: [])
        }
    }
}

extension Project {
    /// The project path of each image file: one inside the project is used where it is, any other is copied into
    /// `images/` under a free name. The file list shows the copies at once. `created` are the copies, the only
    /// files an undo may trash.
    public func importImages(_ urls: [URL]) throws(ProjectError) -> (paths: [RelPath], created: [RelPath]) {
        let base = root.resolvingSymlinksInPath().path + "/"
        var out: [RelPath] = [], created: [RelPath] = []
        defer { if !created.isEmpty { rescan() } }
        for u in urls {
            let path = u.resolvingSymlinksInPath().path
            if path.hasPrefix(base), let p = RelPath(String(path.dropFirst(base.count))) { out.append(p); continue }
            let p = try freeImagePath(ImageInsert.kebabName(u.lastPathComponent))
            do { try FileManager.default.copyItem(at: u, to: url(for: p)) } catch { throw .operationFailed(error.localizedDescription) }
            created.append(p)
            out.append(p)
        }
        return (out, created)
    }

    /// Writes pasted PNG data to `images/pasted-<date>.png` (a free name) and returns its path.
    public func addPastedImage(_ png: Data, at date: Date = .now) throws(ProjectError) -> RelPath {
        let p = try freeImagePath(ImageInsert.pastedName(at: date))
        do { try png.write(to: url(for: p), options: .withoutOverwriting) } catch { throw .operationFailed(error.localizedDescription) }
        rescan()
        return p
    }

    private func freeImagePath(_ name: String) throws(ProjectError) -> RelPath {
        let folder = RelPath(ImageInsert.folder { isDirectory(RelPath($0)!) })!
        do { try FileManager.default.createDirectory(at: url(for: folder), withIntermediateDirectories: true) } catch { throw .operationFailed(error.localizedDescription) }
        let free = ImageInsert.uniqueName(name) { RelPath.make($0, in: folder).map(exists) ?? true }
        guard let p = RelPath.make(free, in: folder) else { throw .invalidName(name) }
        return p
    }
}
