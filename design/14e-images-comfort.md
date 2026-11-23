# 14e. Images into the document, and writing comfort

Lane E. This covers images by drop and paste, editor font size, themes, Focus Mode, the split editor and heading folding.
Code: `Packages/Typo/Sources/TypoKit/{ImageInsert,EditorTheme,EditorPanes,Folding}.swift` and
`App/{ImageDrop,EditorStyle,EditorLayout,EditorFolding}.swift`, plus small hooks in the shared files listed at the end.

## Images

- **Triggers.** You can drop image files (png, jpg/jpeg, gif, svg, webp, pdf) on a `.typ` editor, or paste them.
  A paste can be image file URLs (copied in Finder) or bitmap data (a screenshot).
  - A drop is handled only when *every* dropped file is an image.
  - Bitmap data counts only when the pasteboard carries no text. Apps often put both; then the text wins.
  - Everything else is NSTextView's own behavior. That covers non-image drops, plain-text paste and any non-Typst file.
  - Overrides on `EditorTextView` (`ImageDrop.swift`): `acceptableDragTypes` adds `.fileURL`; also
    `draggingEntered`, `draggingUpdated`, `performDragOperation` and `paste`.
  - A plain NSTextView already accepts Finder file drags through `NSFilenamesPboardType` (checked), so adding
    `.fileURL` leaves non-image drops as they were.
- **Where the file goes** (`Project.importImages`, `Project.addPastedImage`).
  - A file already inside the project is referenced where it is. The check compares symlink-resolved paths, as
    `dropItems` does.
  - Any other file is copied into `images/` at the project root. The folder is created if needed.
  - Free names are `name.png`, `name-2.png`, … (`ImageInsert.uniqueName`).
  - Pasted bitmaps are encoded as PNG in the app (`NSBitmapImageRep`). They are written to
    `images/pasted-yyyyMMdd-HHmmss.png` in local time, with the same uniqueness.
  - The tree is rescanned at once, so the sidebar shows the new file.
- **Copying happens synchronously inside `performDragOperation`.** The sandbox grants access to dropped files only
  during the drop.
- **What gets inserted** (`ImageInsert.snippet`). The image path is relative to the edited file's folder
  (`ImageInsert.relativePath`).
  - Markup gets a figure, placed on its own lines (`TableCode.place`) with the caret in `caption: [|]`:
    `#figure(\n  image("…", width: 80%),\n  caption: [],\n) <fig:stem>`
  - Code mode gets `image("…")`, math gets `#image("…")`, and a string, raw or comment gets the bare path.
  - Several files give several figures, separated by a blank line.
  - The label is the file stem, lowercased. Characters that Typst labels do not allow become `-`, and an empty result
    becomes `image`.
- **One undo step.** The insertion goes through the coordinator's `replace` (one `insertText`). Copying the file is
  not undone.

## Font size

- **Settings.** "Editor font size" ranges from 10 to 24 pt. The default is the system size (13 pt).
- **Shortcuts.** In the View menu: Bigger Text ⌥⌘+, Smaller Text ⌥⌘−, Default Text Size ⌥⌘0. ⌘+, ⌘− and ⌘0 stay
  with the preview zoom.
- **Storage.** The value is stored in UserDefaults (`editorFontSize`, through `@AppStorage`). The app passes it to
  `Highlighter.configure(_:fontSize:)`, so core never reads settings.
- **When it changes:**
  - Every open buffer of every open project is repainted as one attribute-only edit (`Project.restyleBuffers`). That
    edit adds no undo entry, sends no engine message and makes nothing dirty.
  - Each editor refreshes its typing attributes.
  - The ruler (size − 3 pt, and a gutter wide enough for four digits plus the fold triangles), the pills (size − 3),
    the completion list (size − 1, row height follows) and the hover card (size − 1) read `Highlighter.fontSize`.
  - The Focus Mode column is recomputed.
  - `EditorStyle.apply` is idempotent. Every editor calls it on update, and only a real change repaints.

## Themes

- **Settings.** The "Editor theme" picker offers Default (the previous Xcode-like system colors, unchanged),
  Solarized, GitHub and Dracula.
- **Data.** One table per theme in `EditorTheme.swift` (core, platform colors behind `#if canImport(AppKit)`). Each
  table sets text, background, current-line band, selection (key and inactive), ruler numbers (normal and current) and
  the syntax roles.
  - Every theme maps roles to tags the same way. The unit color is the number color pulled 45 % toward math.
- **Appearance.** A theme with both variants (Solarized, GitHub) is built from dynamic colors, so it follows the
  system appearance with no recolor. Dracula is dark only: the editor's scroll view is forced to `darkAqua`, so the
  caret, scroller, find bar and system colors match it.
- **Applying it live.** The text background and the scroll view background are set. The ruler paints the theme
  background (Default keeps the system ruler). The current-line band and selection come from the theme. Buffers
  repaint as with the font size.
- **Popups.** The completion list and the hover card take the editor's effective appearance. Hover text uses the
  theme's colors, so Dracula's light text stays readable under a light system appearance.
- **Identity.** A theme's syntax map is built once, so colors keep their identity across reconfiguration. Tests
  compare color identity.

## Focus Mode

- **Toggle.** View ▸ Focus Mode, ⇧⌘↩. Esc also exits.
  - Plain Esc normally asks for completion (`cancelOperation:` → `complete:`). In Focus Mode, Esc with no completion
    list showing exits the mode instead.
  - ⌥Esc and F5 still complete.
- **What it does:**
  - Hides the sidebar (the `NavigationSplitView` column visibility goes to `.detailOnly`; the previous visibility is
    restored on exit).
  - Hides the preview (`showsTrailing` becomes `!poppedOut && !focus`, so a popped-out preview stays popped out).
  - Hides the second editor pane and the line-number ruler.
  - Centers the text in a column of 72 characters of the current font: `textContainerInset.width` is recomputed on
    every resize of the text view.
- **Typewriter scrolling.** The Settings toggle "Typewriter scrolling in Focus Mode" keeps the caret line vertically
  centered. It acts on every selection change caused by a key press: typing, arrows, find next.
  - To let the first and last lines reach the middle, the vertical inset becomes half the visible height.
  - Limit: a purely vertical window resize does not recompute that inset until the next width change or edit.

## Split editor

- **Toggle.** View ▸ Split Editor, ⌃⌘T. It is disabled in Focus Mode.
- **Layout.**
  - A second editor pane opens to the right of the first. It sits in a nested `SplitPanes` inside the leading side of
    the editor/preview split, with its own autosaved divider. The preview stays.
  - The bottom bar spans both panes.
  - The second pane has a header with a file popup and a close button. The popup lists the project's text files,
    except the one in the first pane.
- **Fixed rules:**
  1. **One storage, one view.** The two panes never show the same file. One `NSTextStorage` reports its edits to one
     content storage only, and detaching it anywhere drops that link. A spike showed the layout of the remaining view
     going corrupt: `"YoneX\ntwotwo\n"`.
     - The parent computes the second pane's file. A render that would duplicate it shows the placeholder instead.
     - When the first pane opens the second pane's file (a sidebar click or a jump), the panes trade files.
     - Every swap goes through `NSTextContentStorage.adopt`. It makes a content storage that still holds the storage let
       go first, so the order in which SwiftUI updates the two panes does not matter. A test covers this.
  2. **Jumps go to the first pane.** Preview clicks, diagnostics, outline and search set `selectedFile`. Only the
     first pane consumes a buffer's pending selection.
  3. **Commands act on the focused pane.** The Format menu, the bottom bar, table insertion and citation insertion act
     on the pane whose text view has keyboard focus. `EditorActions.editor` and `TableEditing.editor` are set when a
     text view becomes first responder, not on every update. Until any pane has had focus, the first pane holds them.
     The fold commands follow the same rule.
  4. **The focused pane drives the preview.** While the second pane has focus, `Project.focusedEditorFile` names its
     file. Preview cursor sync and completion (`Project.live`) use `focusedEditorFile ?? selectedFile`, and an
     unfocused second pane reports no caret.
  5. **Each pane keeps its own caret per file.** The first pane keeps it on the buffer (as before). The second pane
     keeps it in `EditorLayout.secondCarets`, keyed by buffer identity, so renames do not lose it.

## Folding heading sections

- **Regions** (`Folding.regions`, pure).
  - A heading line is a line whose first non-blank character starts a `.heading` span of the syntax mirror. That
    excludes raw blocks, `- = list items` and `#[= content]`.
  - The heading line's level is its count of `=`.
  - A fold hides the lines from the one after the heading to the one before the next heading of the same or a higher
    level, or to the end of the file. A heading with nothing below it has no fold.
- **State.** Folds are kept on the `Buffer` (`folding`): heading line starts plus the cached regions and merged hidden
  ranges. So folds survive file switches and pane changes. They are not persisted across window closes.
- **Hiding.** `FoldController`, the `NSTextContentStorageDelegate` of each editor, answers
  `textContentManager(_:shouldEnumerate:options:)` from the buffer's hidden ranges.
  - Whenever the buffer's `foldRevision` changes it invalidates the document's layout. That covers folds made by a
    command and folds an edit opened (via `NSTextStorage.didProcessEditingNotification`, deferred until the edit has
    been processed).
  - The app then lays out the viewport synchronously, so the text view's height and scroller follow at once. In a
    spike a 5054 pt document folded to 394 pt.
- **Edits.** Typing never edits hidden text. An edit touching a fold opens that fold in `Buffer`'s
  `willProcessEditing`, so typing, undo, Replace All and other features' `project.edit` all go through it. Touching
  means:
  - changing hidden text or the heading line's line break;
  - inserting at the end of the heading line;
  - appending to a folded last section.

  Folds before or after an edit move with the text. A fold whose heading stops being a heading is dropped.

  A heading level edited while a fold is closed can change the fold's extent; for example, `== A2` becoming
  `=== A2` makes a closed `== A1` reach the next `=`.
  - If the new extent covers the edited text, that fold opens, so the line being typed never disappears.
  - Any other change of the hidden ranges, beyond the edit's own shift, bumps `foldRevision`, so the layout follows.
- **Selection** (`FoldController.selection`, called from the text view's `willChangeSelection` delegate).
  - A caret the keyboard moves into hidden text steps over the fold. Going forward it lands at the next visible line.
    Going back it lands at the end of the heading line. TextKit 2 already skips folds for up and down, but `moveRight`
    lands inside, so this is needed.
  - Any other selection with an end inside hidden text opens the folds there first. That covers find (the text finder
    sets `selectedRanges`), jumps (also opened explicitly before `setSelectedRange` in `updateNSView`) and a restored
    caret.
  - A selection that spans a whole fold with both ends visible leaves it closed.
  - During a file switch the delegate leaves the selection alone. A test showed TextKit keeps the incoming file's folds
    even without this guard; the guard is insurance.
- **After folding** (and after a file switch), a caret or selection end that is now hidden moves to the end of the
  heading line.
- **What you see:**
  - A disclosure triangle in the ruler on every heading line that can fold. A click on that row toggles the fold.
  - A "⋯ N lines" badge after a folded heading's text. A click on it unfolds.
  - Line numbers skip hidden lines: numbers count newlines up to each laid-out paragraph.
  - A diagnostic inside a folded section shows its pill on the heading line (`Buffer.visibleLine`).
  - The current-line band is always on a visible line, because the caret never stays hidden.
- **Commands** (View menu, focused pane): Fold Section ⌥⌘←, which folds the innermost open section around the caret,
  so repeating it folds outward. Unfold Section ⌥⌘→, Fold All Sections ⇧⌥⌘←, Unfold All Sections ⇧⌥⌘→.

## Tests

| Suite | What it covers |
|---|---|
| `ImageInsertTests` | Naming, the pasted name in given time zones, relative paths (root, subfolder, sibling, same folder), labels, snippets per mode, copy versus in-place through the `/var` → `/private/var` symlink, and pasted data. |
| `EditorStyleTests` | Default reproduces the old map; two-variant themes differ per appearance; Dracula is fixed; fonts per size; a restyle repaints an open buffer without an undo entry or dirtiness. The shared style is changed and restored with no suspension in between. |
| `EditorPaneTests` | A storage moving between two real TextKit 2 views in the order that used to corrupt layout; completion following `focusedEditorFile`. |
| `FoldingTests` | Region computation, real-heading detection, nested merge, the edit-touch rule, selection resolution, and Buffer folds through edits (`project.edit` included). In a real NSTextView: hidden lines skipped, ruler-style numbers skipping correctly, typing at the heading end reopening with the deferred relayout, heading-level edits reshaping a closed fold with the layout matching the hidden ranges, and a file switch (with the selection delegate in place) keeping the folds. The view's delegate path is covered too: arrows stepping over folds, a find selection via `selectedRanges` opening a fold, and a programmatic jump opening nested folds with a non-zero caret rect. |

The full suite has 213 tests. TypoKit also builds for the iOS Simulator.

Not covered by tests (needs the running app): drag and drop and paste from Finder or a screenshot, the menus and
shortcuts, visuals of each theme, the Focus Mode column and typewriter scrolling, the split layout and focus routing,
and ruler and badge clicks.

## Shared-file hooks

- `EditorView.swift`: new parameters (`layout`, `focusMode`, `isPrimary`) and the settings `@AppStorage`.
  - Calls added: `applyStyle`, `applyFocus` and `setUpFolding`.
  - Swaps use `adopt` and the per-pane caret.
  - `isPrimary` gates the pending selection, which reveals folds first.
  - Focus-based editor claiming, Esc in `doCommandBy`, `typewriterScroll` and a ruler draw hook.
  - `replace` and `textView` lost `private`.
- `EditorDecorations.swift`: theme colors, size-based pill font, fold badge and pill-line mapping.
- `ProjectView.swift`: column visibility, preview hidden in Focus Mode, and `EditorPane` restructured around the
  nested split.
- `App.swift`: one `.commands` line.
- `SettingsView.swift`: three controls.
- `CompletionPopup.swift` and `HoverPopup.swift`: font sizes and the editor's appearance.
- Core: `Highlighter` (configurable style and size), `Hover` (size), `Buffer` (fold state and two edit hooks;
  `recolor` internal), `Project` (`focusedEditorFile`).
