import Foundation
import TypstEngine

/// Edits newer than the latest delivered compile. Lives on the main actor in Project.
struct EditLog {
    private(set) var entries: [Edit] = []
    mutating func append(_ e: Edit) { entries.append(e) }
    mutating func trim(through seq: Seq) { entries.removeAll { $0.seq <= seq } }

    /// A file or folder moved: entries of files at or under `old` now name their new paths.
    mutating func relocate(from old: RelPath, to new: RelPath) {
        entries = entries.map { e in
            guard let f = e.file.replacing(old, with: new) else { return e }
            return Edit(seq: e.seq, file: f, range: e.range, replacement: e.replacement, newLength: e.newLength)
        }
    }

    /// Maps a range computed at `seq` into the current text of `file`. Pure.
    /// An edit wholly before (or inserting at the start) shifts the range. An edit wholly after leaves it.
    /// Overlap -> nil.
    func map(_ range: NSRange, in file: RelPath, from seq: Seq) -> NSRange? {
        var r = range
        for e in entries where e.seq > seq && e.file == file {
            if NSMaxRange(e.range) <= r.location {
                r.location += e.replacement.utf16.count - e.range.length
            } else if e.range.location >= NSMaxRange(r) {
                continue
            } else {
                return nil
            }
        }
        return r
    }
}
