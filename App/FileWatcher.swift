import CoreServices
import Foundation

/// FSEvents on the project root at file level. Structural events (created, removed, renamed) that `isStructural`
/// accepts rescan the tree; other changes to a file `isOpen` accepts only reload it from disk (the autosave writes
/// every 1.5 s and must not rescan the tree). Events arrive coalesced (0.3 s).
@MainActor final class FileWatcher {
    struct Flags: OptionSet {
        let rawValue: UInt32
        static let created = Flags(rawValue: UInt32(kFSEventStreamEventFlagItemCreated))
        static let removed = Flags(rawValue: UInt32(kFSEventStreamEventFlagItemRemoved))
        static let renamed = Flags(rawValue: UInt32(kFSEventStreamEventFlagItemRenamed))
        static let modified = Flags(rawValue: UInt32(kFSEventStreamEventFlagItemModified))
    }

    private final class Box {
        let isStructural: @MainActor (String, Flags) -> Bool
        let isOpen: @MainActor (String) -> Bool
        let onChange: @MainActor () -> Void
        let onContent: @MainActor () -> Void
        init(_ isStructural: @escaping @MainActor (String, Flags) -> Bool, _ isOpen: @escaping @MainActor (String) -> Bool,
             _ onChange: @escaping @MainActor () -> Void, _ onContent: @escaping @MainActor () -> Void) {
            self.isStructural = isStructural
            self.isOpen = isOpen
            self.onChange = onChange
            self.onContent = onContent
        }
    }

    private var stream: FSEventStreamRef?
    private let box: Unmanaged<Box>

    init?(root: URL, isStructural: @escaping @MainActor (String, Flags) -> Bool, isOpen: @escaping @MainActor (String) -> Bool,
          onChange: @escaping @MainActor () -> Void, onContent: @escaping @MainActor () -> Void) {
        box = .passRetained(Box(isStructural, isOpen, onChange, onContent))
        var context = FSEventStreamContext(version: 0, info: box.toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info, let paths = unsafeBitCast(paths, to: CFArray.self) as? [String] else { return }
            let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated {     // the stream is scheduled on the main queue
                let changed = (0..<count).contains { i in
                    let f = Flags(rawValue: flags[i]).intersection([.created, .removed, .renamed])
                    return !f.isEmpty && box.isStructural(paths[i], f)
                }
                if changed { box.onChange(); return }
                // An atomic replace by another tool reports a rename or creation of the (known) path.
                if (0..<count).contains(where: { !Flags(rawValue: flags[$0]).intersection([.created, .renamed, .modified]).isEmpty && box.isOpen(paths[$0]) }) {
                    box.onContent()
                }
            }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
        guard let s = FSEventStreamCreate(nil, callback, &context, [root.path] as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags) else {
            box.release()
            return nil
        }
        FSEventStreamSetDispatchQueue(s, .main)
        guard FSEventStreamStart(s) else {
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            box.release()
            return nil
        }
        stream = s
    }

    isolated deinit {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        box.release()
    }
}
