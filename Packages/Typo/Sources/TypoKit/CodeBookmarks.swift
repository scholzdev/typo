import Foundation
import TypstEngine

/// A line the user bookmarked (Xcode's line bookmarks), or a whole file. A line bookmark stays with its line while text
/// is edited around it and goes away when the line is deleted. Not to be confused with security-scoped URL bookmarks
/// (`ScopedAccess`).
public struct CodeBookmark: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var path: RelPath
    /// 0-based; 0 for a file bookmark.
    public var line: Int
    /// Empty: the navigator shows the line's text.
    public var title = ""
    public var note = ""
    public var done = false
    /// The navigator group it is in; empty for none.
    public var group = ""
    /// Bookmarks the whole file rather than a line.
    public var isFile = false

    public init(id: UUID = UUID(), path: RelPath, line: Int, isFile: Bool = false) { self.id = id; self.path = path; self.line = line; self.isFile = isFile }

    /// The title, else Xcode's "file: line" for a line and the file's name for a file.
    public var displayTitle: String {
        if !title.isEmpty { return title }
        if isFile { return path.name }
        return "\(path.name.split(separator: ".").first.map(String.init) ?? path.raw): \(line + 1)"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        path = try c.decode(RelPath.self, forKey: .path)
        line = try c.decode(Int.self, forKey: .line)
        title = try c.decode(String.self, forKey: .title)
        note = try c.decode(String.self, forKey: .note)
        done = try c.decode(Bool.self, forKey: .done)
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? ""          // absent before groups existed
        isFile = try c.decodeIfPresent(Bool.self, forKey: .isFile) ?? false
    }

    /// Where `anchor` (a line's range, its line break included) is after `pre` was replaced by `newLength` characters;
    /// nil when the edit removed or replaced the whole line. Text inserted at the line's start pushes the line down.
    public static func shift(_ anchor: NSRange, by pre: NSRange, newLength: Int) -> NSRange? {
        let s = anchor.location, e = NSMaxRange(anchor), a = pre.location, b = NSMaxRange(pre), delta = newLength - pre.length
        if b <= s { return NSRange(location: s + delta, length: anchor.length) }
        if a >= e { return anchor }
        if a <= s && b >= e { return nil }
        let start = a < s ? a + newLength : s
        let end = b >= e ? a + newLength : e + delta
        return NSRange(location: start, length: max(end - start, 0))
    }

    /// The 0-based line `offset` is on (LF line breaks, as buffers hold them).
    public static func line(at offset: Int, in text: NSString) -> Int {
        var n = 0, buffer = [unichar](repeating: 0, count: 4096), pos = 0
        let end = min(offset, text.length)
        while pos < end {
            let k = min(buffer.count, end - pos)
            text.getCharacters(&buffer, range: NSRange(location: pos, length: k))
            for i in 0..<k where buffer[i] == 10 { n += 1 }
            pos += k
        }
        return n
    }

    /// The range of 0-based `line` (its break included), clamped to the last line.
    static func range(ofLine line: Int, in text: NSString) -> NSRange {
        text.lineRange(for: NSRange(location: EditorLocation.offset(ofLine: line + 1, in: text as String), length: 0))
    }
}

/// Stores one project's bookmarks under "Tympan.bookmarks.<project id>", like `ProgressStore`.
public struct BookmarkStore: Sendable {
    nonisolated(unsafe) private let defaults: UserDefaults
    private let key: String

    public init(_ id: ProjectID, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // persisted key, kept from the app's old name so saved data survives
        key = "Tympan.bookmarks.\(id.raw)"
    }

    public func load() -> [CodeBookmark] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([CodeBookmark].self, from: $0) } ?? []
    }

    public func save(_ b: [CodeBookmark]) {
        if b.isEmpty { defaults.removeObject(forKey: key) } else { defaults.set(try? JSONEncoder().encode(b), forKey: key) }
    }
}

extension Notification.Name {
    /// Object: the `Project` whose bookmarks were added, removed, changed or moved to another line.
    public static let bookmarksChanged = Notification.Name("Tympan.bookmarksChanged")
}

extension Project {
    func bookmarksDidChange(from old: [CodeBookmark]) {
        guard bookmarks != old else { return }
        BookmarkStore(id).save(bookmarks)
        NotificationCenter.default.post(name: .bookmarksChanged, object: self)
    }

    public func bookmark(in path: RelPath, line: Int) -> CodeBookmark? { bookmarks.first { $0.path == path && $0.line == line && !$0.isFile } }

    public func bookmarkedLines(in path: RelPath) -> Set<Int> { Set(bookmarks.filter { $0.path == path && !$0.isFile }.map(\.line)) }

    public func fileBookmark(_ path: RelPath) -> CodeBookmark? { bookmarks.first { $0.path == path && $0.isFile } }

    /// Bookmarks the whole file `path`, unless it already is.
    public func addFileBookmark(_ path: RelPath) {
        if fileBookmark(path) == nil { bookmarks.append(CodeBookmark(path: path, line: 0, isFile: true)) }
    }

    /// The navigator's groups by name.
    public var bookmarkGroups: [String] { Set(bookmarks.map(\.group)).subtracting([""]).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }

    /// Puts the bookmarks `ids` in `group` (a new or existing name); "" takes them out of any group.
    public func moveBookmarks(_ ids: Set<UUID>, toGroup group: String) {
        bookmarks = bookmarks.map { var b = $0; if ids.contains(b.id) { b.group = group }; return b }
    }

    /// Renames a group; deleting one is renaming it to "", which keeps its bookmarks outside any group.
    public func renameBookmarkGroup(_ old: String, to new: String) {
        bookmarks = bookmarks.map { var b = $0; if b.group == old { b.group = new }; return b }
    }

    /// "New Group", or "New Group 2" and so on when that is taken.
    public var newBookmarkGroupName: String {
        let taken = Set(bookmarkGroups)
        return (1...).lazy.map { $0 == 1 ? "New Group" : "New Group \($0)" }.first { !taken.contains($0) }!
    }

    /// Adds a bookmark on 0-based `line`, or removes the one there.
    public func toggleBookmark(_ path: RelPath, line: Int) {
        if let b = bookmark(in: path, line: line) { return removeBookmarks { $0.id == b.id } }
        let b = CodeBookmark(path: path, line: line)
        if let text = buffers[path]?.storage.string as NSString? { bookmarkAnchors[b.id] = CodeBookmark.range(ofLine: line, in: text) }
        bookmarks.append(b)
    }

    public func updateBookmark(_ id: UUID, _ change: (inout CodeBookmark) -> Void) {
        guard let i = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        change(&bookmarks[i])
    }

    public func removeBookmarks(where gone: (CodeBookmark) -> Bool) {
        guard bookmarks.contains(where: gone) else { return }
        bookmarks.removeAll(where: gone)
        bookmarkAnchors = bookmarkAnchors.filter { a in bookmarks.contains { $0.id == a.key } }
    }

    /// File by file (by path), then by line: the order of the navigator and of Next/Previous Bookmark.
    public var sortedBookmarks: [CodeBookmark] {
        bookmarks.sorted { ($0.path.raw, $0.isFile ? -1 : $0.line) < ($1.path.raw, $1.isFile ? -1 : $1.line) }
    }

    /// The bookmark after (or before) 0-based `line` of `path`, across files and wrapping around; nil without any.
    public func adjacentBookmark(from path: RelPath?, line: Int, forward: Bool) -> CodeBookmark? {
        let all = sortedBookmarks
        let here = (path?.raw ?? "", line)
        return forward ? all.first { ($0.path.raw, $0.line) > here } ?? all.first
                       : all.last { ($0.path.raw, $0.line) < here } ?? all.last
    }

    /// Opens the bookmark's file with the caret at the start of its line; a file bookmark just opens the file.
    public func reveal(_ b: CodeBookmark) {
        if b.isFile { return select(b.path) }
        Task {
            guard let buffer = try? await open(b.path) else { return }
            let start = EditorLocation.offset(ofLine: b.line + 1, in: buffer.storage.string)
            show(b.path, range: NSRange(location: start, length: 0))
        }
    }

    /// The bookmark's line from its open buffer, trimmed; nil when the file isn't open (then `bookmarkSnippets` reads disk).
    public func openSnippet(_ b: CodeBookmark) -> String? {
        guard !b.isFile, let text = buffers[b.path]?.storage.string as NSString? else { return nil }
        return text.substring(with: CodeBookmark.range(ofLine: b.line, in: text)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Each bookmark's line, trimmed: an open buffer's text, otherwise the file on disk.
    public func bookmarkSnippets() async -> [UUID: String] {
        var texts: [RelPath: NSString] = [:]
        for p in Set(bookmarks.filter { !$0.isFile }.map(\.path)) {
            if let b = buffers[p] { texts[p] = b.storage.string as NSString }
            else if let t = try? await Self.readText(url(for: p), settings: textFileSettings()) { texts[p] = t as NSString }
        }
        var out: [UUID: String] = [:]
        for b in bookmarks where !b.isFile {
            guard let text = texts[b.path] else { continue }
            out[b.id] = text.substring(with: CodeBookmark.range(ofLine: b.line, in: text)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return out
    }

    /// A buffer was created from the disk text the saved lines refer to.
    func anchorBookmarks(in b: Buffer) {
        let text = b.storage.string as NSString
        for m in bookmarks where m.path == b.path && !m.isFile { bookmarkAnchors[m.id] = CodeBookmark.range(ofLine: m.line, in: text) }
    }

    /// From the buffer's edit funnel: anchors follow the edit, bookmarks of deleted lines go.
    func bookmarksEdited(_ path: RelPath, _ pre: NSRange, newLength: Int, text: NSString) {
        guard !bookmarkAnchors.isEmpty else { return }
        var next = bookmarks, changed = false
        next.removeAll { m in
            guard m.path == path, let a = bookmarkAnchors[m.id] else { return false }
            if let moved = CodeBookmark.shift(a, by: pre, newLength: newLength) { bookmarkAnchors[m.id] = moved; return false }
            // The line sat inside replaced text. Only a deletion removes it: a reload or reformat replaces the whole
            // text, and the bookmark keeps its place by line within the new text instead of vanishing.
            guard newLength > 0 else { bookmarkAnchors[m.id] = nil; changed = true; return true }
            let first = CodeBookmark.line(at: pre.location, in: text)
            let last = CodeBookmark.line(at: pre.location + newLength - 1, in: text)   // not the empty line after a final break
            bookmarkAnchors[m.id] = CodeBookmark.range(ofLine: min(max(m.line, first), last), in: text)
            return false
        }
        for i in next.indices where next[i].path == path {
            guard let a = bookmarkAnchors[next[i].id] else { continue }
            let line = CodeBookmark.line(at: a.location, in: text)
            if line != next[i].line { next[i].line = line; changed = true }
        }
        if changed { bookmarks = next }
    }
}
