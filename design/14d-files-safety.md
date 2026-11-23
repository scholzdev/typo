# 14d. File safety: path references, deleted files, undo, snapshots

Extends section 13 (file management). Built for a thesis writer whose project is a tree of chapters, figures and a
bibliography: renaming or moving one must not break the build, and no text may be lost silently.

This removes three items from DESIGN 13:
- "References in other files (`#include "kapitel.typ"`) are NOT rewritten" (now offered after every rename or move).
- "Known limits: no undo for file operations" (rename, move, new file, new folder, duplicate and Move to Trash are undoable).
- "a file deleted outside the app while it is open in a buffer is not detected" (it is detected and never recreated silently).

## 1. Update path references after a rename or move

Core, pure: `PathReferences.edits(in:of:moving:to:existing:)` (`PathReferences.swift`). For every `.string` token of
`TypstSyntax.tokens`:
- The contents (without the quotes) resolve like Typst does: relative to the containing file's folder, a leading `/`
  means the project root, `.` and `..` are normalized. Skipped: empty strings, package specs (`@…`), URLs (`://`),
  a `..` above the root, strings with escapes (`\`, not decoded), and anything that did not resolve to a file or folder
  that existed before the move. Comments and markup quotes are never `.string` tokens, so they are never touched.
- The target maps through the move (the moved item itself or a descendant), the containing file takes its new
  location (it may have moved inside a moved folder), and the string is rewritten to reach the target from there in the
  original style: `/…` stays root-based; a relative one stays relative with `../` as needed, keeping a leading `./`
  and a trailing `/`. `"` and `\` in new names are escaped. Only strings whose text changes produce a replacement, so a
  file that moved together with its targets keeps its relative strings, and a moved file's own `../` paths are fixed.

Integration: `Project.referenceUpdates(moving:to:)` reads every `.typ` file (an open buffer's text, else the disk)
and the set of existing files and folders BEFORE the move. `Project.updateReferences(_:)` runs only after the move
succeeded: it opens each file's buffer and applies the replacements as one undo step per file ("Update References",
the `project.edit` funnel). The replacements are recomputed on the file's current text at that moment; every input is
still the pre-move one (old path, existing set), so the result is the same unless the text changed while the move
awaited its saves, in which case the old ranges would have been wrong.

App (`FilesController.relocate`, `App/FileHistory.swift`): sidebar rename, the File menu's Rename and a drag onto a
folder all go through it. After the move, if there are updates, an alert "Update N references in M files?" lists the
files (informative text) with "Update" (default) and "Don't Update". A failed move shows its error and edits nothing.
Drags now move each row through this path (and import Finder items with `importItems`); `Project.dropItems` stays in
core with its tests but the app no longer calls it.

## 2. Files deleted outside the app

- `Project.missingFiles` (observable) is re-derived from the disk for every open buffer (`checkMissing`) on each
  `refreshFiles` (FSEvents watcher, app activation), before the "tree unchanged" early return, so a coalesced
  delete-and-recreate or a tree already rescanned by a file operation cannot hide it. It is also re-derived after a
  relocate and a Trash. `Buffer.isMissingOnDisk` reads it.
- `save(under:)`, the single write choke point (autosave, Cmd-S, quit, window close, quiesce, duplicate), writes
  only buffers whose file still exists; a dirty buffer whose file is gone is marked instead of written, which also
  covers the 0.3 s before the watcher reports the deletion. Invariant: a save only overwrites existing files.
  `quiesceAndSave` ignores missing buffers, so moving or trashing a folder that holds one cannot loop forever.
- A file that reappears (git checkout) clears the mark on the next refresh.
- App: `MissingFileBanner` (placed in `ProjectView`) shows "“x.typ” was deleted outside Typo." with
  "Save Again" (`saveAgain`: recreates missing folders and writes the buffer's text even when clean) and "Close"
  (`closeMissing`: the Trash protocol's close step, extracted as `forget`, then the main document is shown).
- Quit and window close (decision): they are never blocked, and unsaved text is not dropped without asking. A missing
  buffer with unsaved changes keeps `hasUnsavedChanges` true, so quit goes through `saveUntilResolved`, which first
  asks per such file "Save Again" or "Don't Save" (`confirmMissingFiles`, one line in App.swift). A missing file
  without unsaved changes is not asked about: nothing would be lost.

### Renamed or moved in Finder
`Project.identities` keeps the `fileResourceIdentifier` of each open buffer's path, captured at open, after every save write (the atomic write gives the file a new one) and refreshed in `refreshFiles`. When `refreshFiles` finds a buffer whose path is gone, `followExternalMoves` looks for a scanned path that was not in the previous tree, has no buffer and the same identity, and re-keys the buffer through `rekeyOpenItems`, the tail `relocate` also uses. Files are matched one by one, so a folder rename works. Text, dirty state and `selectedFile` follow. No match (moved out, Trash, other volume): missing + banner.

## 3. Undo for file operations

- The window's undo manager (SwiftUI `@Environment(\.undoManager)`, handed to `FilesController` by the
  `.fileHistory(files)` modifier in ProjectView) holds the file operations. Cmd-Z reaches it while the sidebar has
  focus; the text view keeps using the buffer's own manager.
- Action names: Rename, Move, New File, New Folder, Duplicate, Move to Trash ("Undo Rename", ...).
- `FileUndo` is "the way back", and performing it returns the way forward again: rename/move go back by relocating
  (`rename(new, to: old.name)` or `move(new, into: old.parent)`, through the same reference offer); New File, New Folder
  and Duplicate are undone by moving the item to the Trash; Move to Trash is undone by moving the item back from the
  Trash URL. The trash hook now returns that URL (`Project.trash: (URL) throws -> URL`, `moveToTrash` returns it; the
  tests' fake trashes return their sink URL), and `Project.restore(fromTrash:to:)` moves it back under the file-op lock.
- Redo: the undo handler registers the way forward synchronously, while the manager is still undoing, so it lands on
  the redo stack; the async operation starts after and the redo awaits its result (the Trash URL is only known then).
- A failure shows "Couldn't Undo …"/"Couldn't Redo …". Putting an item back from the Trash fails in the sandbox
  (the app cannot reach ~/.Trash); the alert then says to use Put Back in Finder.

## 4. Snapshots (local history)

- After a save that wrote something (`save(under:)` success), when the last snapshot is 10 minutes old or none was
  taken since the project opened, every text file (`FileKind.isText`; an open buffer's text, else the file) is copied
  off the main actor into `Application Support/Typo/Snapshots/<SHA-256 of the standardized root path>/<ISO-8601
  time with milliseconds>/<path>`. It is written to a hidden temp folder and renamed into place, so a half snapshot
  never shows. Snapshot write errors are ignored (a safety net, not a save).
- Retention after each snapshot: everything from the last 24 hours, then the newest of each day (by age from now) for
  30 days, at most 200 in all.
- `Project.history.folder` is nil by default and set only by the app (`.fileHistory` modifier), so the test suite never
  writes to the real Application Support; tests set a temp folder and inject the clock (`history.now`).
- App: File ▸ Snapshots… (`SnapshotCommands`, one line in App.swift, in `CommandGroup(after: .newItem)`) opens an
  AppKit sheet on the project window (`SnapshotsView`): snapshots with relative date and the number of files that differ
  from the current text; a selected snapshot lists its files as Changed / Unchanged / Missing with a read-only preview.
  "Restore File" and "Restore All Changed Files" replace the current text through the buffer as one undo step per
  file ("Restore File"; Cmd-Z in that file's editor takes it back); a missing file (and its folders) is created again
  through `createFolder`/`createFile` first. "Take Snapshot Now" ignores the 10-minute rule.

## Name clash on a drop
Dropping a project item onto a folder that holds that name asks like Finder: "An item named “x” already exists in this location." with Keep Both (default; `availableName`, "x 2.typ"; `move(_:into:named:)`), Stop (the rest of the drop is skipped, earlier moves stay) and Replace. Replace is `Project.replacing` (Move to Trash of the old item, then the move); its undo, `undoReplacing`, moves the item back first and then restores the trashed one, as one `FileUndo` step (`FileUndo.replaced`). Finder imports keep the silent " copy" suffix.

## Changed on disk
An open file whose content changes outside the app (another editor, a sync tool, `git pull`) is reloaded instead of being
overwritten by the next autosave. `Project.diskHashes` remembers, per open buffer, the hash of the text last read from or
written to disk (set in `open`, after each save write, after a reload; moved with the buffer on rename, dropped on close).
`reloadChangedFiles()` (ExternalChanges.swift; called by `refreshFiles` after `checkMissing`, and by the watcher) reads each
open file off-main and compares:

- same hash: nothing (our own writes update the hash first, so they never count; a read that overlaps a save or reload is
  discarded and retried at the next event);
- different and the buffer is clean: the disk text replaces the buffer as one edit over the differing middle only (the
  caret and folds stay), one undo step "Reload from Disk", then the buffer is marked saved and no write follows;
- different and the buffer is dirty: a conflict, `Project.changedOnDisk` (observable). `save` and `quiesceAndSave` skip it
  like a missing file. `keepMine(path)` writes the buffer over the disk; `useDisk(path)` loads the disk text.

App: `FileWatcher` also reports `ItemModified`/created/renamed events of open files (`FilesController.isOpenFile`), which
run only `reloadChangedFiles`, not a tree rescan; structural events still rescan (which reloads too), and app activation
reloads. `ChangedOnDiskBanner` above the editor: "“x” was changed on disk." with Use Disk Version and Keep Mine.
Quit asks per conflicted file (`confirmChangedFiles`). Undoing a reload makes the buffer dirty again, so the next save
writes the older text on purpose.

## Limits

- Undoing a rename does not undo the reference edits (they are separate undo steps in each file); the reverse move
  offers the reverse updates instead.
- Undo of Move to Trash puts the files back but not the closed buffers' undo history, and not `main` if the Trash had
  moved the preview to another document. In the sandboxed app it usually ends in the Put Back alert.
- An open file renamed or moved in Finder inside the project is followed by file identity (section 2); moves out of the root or across volumes still show the banner, and external moves get no reference-update offer. The sidebar selection (`model.listSelection`) is not remapped for an external move.
- Replace in the name-clash prompt skips the reference-update offer.
- A file changed on disk and renamed in Finder in the same 0.3 s window is followed only when the change was in place;
  an atomic replace gives it a new identity, so it shows the missing-file banner.
- Changed-on-disk detection compares text hashes, so a change that restores the same text is no change; a file that is not
  valid UTF-8 is never reloaded.
- A leftover hidden temp folder from a crash mid-snapshot is not cleaned up.

## Tests (TypoKit, 17 new; suite 205; +6 in FileSafetyTests: Finder rename (dirty, after save, folder), move out of the root, replace + undo, Keep Both name)

- `PathReferenceTests`: rename referenced as `"a.typ"`, `"./a.typ"`, `"/a.typ"`, `"../a.typ"`; a moved folder with an
  image referenced from outside (relative and `/`); a moved file's own relative includes; files moving together keep
  their relative strings; non-paths, package specs, comments, markup quotes, URLs, empty strings and `..` above the root
  stay; integration: rename updates an open dirty buffer and a closed file, recomputed after typing, one undo step each.
- `FileSafetyTests`: deleted file marked and never recreated until Save Again; a save before the watcher noticed does
  not recreate; Save Again writes a clean buffer and its folder; a file that comes back clears the mark; Close drops the
  buffer and shows the main; renaming a folder with a missing dirty file finishes; rename back keeps the buffer, its
  text and the selection; a trashed folder comes back from a fake Trash, and putting back onto a taken name fails.
- `SnapshotTests`: snapshot on save with the 10-minute rule (injected clock, text files only, no snapshot for an empty
  save); retention pruning; restore goes through the buffer as one undo step and recreates a missing file and folder.
