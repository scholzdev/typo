# 14h Editor tabs

## What it does
An Xcode-style tab bar above each editor pane (one bar; two when the editor is split). Tabs are files.
- A sidebar single click, a jump (diagnostic, outline, preview click) or a new file opens the file as the italic
  preview tab; the next such open replaces it in place.
- A double click on a sidebar text file, a double click on the tab, or the first edit makes the tab permanent
  (`TabList.makePermanent`, `Project.makeTabPermanent`).
- Each tab has a close button; an unsaved buffer shows a dot instead (the close button while hovered).
- Clicking a tab shows that file (and leaves Quick Look). A tab bar scrolls horizontally when full. Two tabs
  with the same name show their folder.
- Pinned tabs (like a browser's): Pin Tab / Unpin Tab in the tab's context menu. A pinned tab moves to the left
  (pinned tabs in the order they were pinned), is permanent (never the preview), shows a pin glyph instead of the
  close button and cannot be closed: not by the menu, Close Other Tabs, a middle click or ⌘W (the tab stays; ⌘W does
  nothing to it and the window does not close). Trashing or moving the file still removes/rekeys it. Pinned state is
  saved with the first pane's tabs (key `pinned`; data without it decodes as no pins).
- Context menu of every tab (both panes): Close Tab (disabled when pinned), Close Other Tabs (keeps pinned tabs;
  disabled when no other unpinned tab), divider, Pin Tab / Unpin Tab.
- A middle click on an unpinned tab closes it. `MiddleClick` (EditorTabs.swift) is an NSViewRepresentable overlay
  whose `hitTest` returns the view only while `NSApp.currentEvent` is a button-2 event; for every other event it
  returns nil, so left clicks (select, double click) and right clicks (context menu) reach the tab as before.
- New tab: a "+" at the end of the first pane's bar and File > New Tab… (⌘T) open a popover picker (Open Quickly
  style): search field focused, the project's text files (name bold, folder dimmed) filtered by `QuickOpen.filter`
  (every word a case-insensitive substring of the path; name matches first), ↑/↓, Return or a click opens the file as
  a permanent tab, Esc closes. ⌘T sets `EditorLayout.quickOpen`; the popover hangs off the "+", so it shows nothing in
  Focus Mode (the bar is hidden). The second pane keeps its own "+" file menu.
- A double click anywhere on a sidebar text file's row (the Label fills the row width) opens it permanently.
- Menus (File and Window): Close Tab ⌘W (closes the focused pane's tab; with no tab left it closes the window),
  Close Window ⇧⌘W, Show Next Tab ⌃Tab and ⇧⌘], Show Previous Tab ⌃⇧Tab and ⇧⌘[.
  `CommandGroup(replacing: .saveItem)` takes over the window's own Close, so only one item has ⌘W.
  Native window tabbing is off (`NSWindow.allowsAutomaticWindowTabbing = false`).
- The first pane's tabs are saved per project (`Typo.tabs.<project id>`) and restored on open, minus files
  that no longer exist; `main` is added when it is not among them.

## Decisions
- Tabs are derived from `selectedFile` (its didSet adds the file as a preview tab), never driven by tab clicks
  alone: about ten code paths set `selectedFile`, and all of them get a tab for free. A tab click just sets
  `selectedFile`. The second pane derives its tabs from `secondFile` the same way.
- Closing never prompts and never loses text: buffers stay open after their tab closes and autosave keeps running.
- One file per pane at a time (a text storage cannot back two text views): showing a file in one pane that the
  other shows trades the files, as the existing swap rule does. Both panes may list the same file as a tab.
- Moves and Finder renames rekey tabs in `rekeyOpenItems`; Trash and "Close" on a missing file remove them in
  `forget`, and the neighbour tab (right, else left) is shown.
- `TabList` (core, pure) holds the rules; `Project.tabs` is publicly readable, changed only by methods
  (`openPermanently`, `makeTabPermanent`, `togglePinTab`, `closeTab`, `closeOtherTabs`).
- The dirty dot refreshes through `Project.dirtyRevision` (bumped when a buffer turns dirty and after each save),
  since `Buffer` is not observable. The same bump pins the second pane's preview tab on its first edit.
- Selecting a text file while Quick Look shows (any change of `selectedFile`) leaves Quick Look.

## Limits
- No drag reordering. No tabs for Quick Look (non-text) files.
- Only the first pane's tabs persist; the second pane's start empty. A rename of the second pane's file drops its
  tab (the second pane never followed renames).
- Close Tab while Quick Look shows closes the (hidden) text tab underneath.
- A second-pane file is chosen from the "+" menu in its bar (the old file popup).

## Tests
`Packages/Typo/Tests/TypoKitTests/TabsTests.swift`: TabList rules (preview replaced in place, permanent
insert after active, no duplicates, close picks right then left, wrap-around neighbour, rekey, Codable); through
Project: selecting adds preview tabs and an edit pins, `openPermanently` pins, a jump adds a preview tab, in-app
move and folder move rekey, a Finder rename rekeys, Trash removes the tab and shows the neighbour, `closeTab` keeps
the buffer and its unsaved text, persistence drops missing files.
Pinned tabs: pin order and position, never preview, unpin placement, close refuses, rekey/remove keep pinned
consistent, Codable with and without the key; through Project: Close Other Tabs keeps pinned, Trash drops a pinned
tab, pinned state persists.
`QuickOpenTests`: empty query keeps all, case-insensitive multi-word substring, name matches before folder matches.

## Bars
Plain SwiftUI placement, no own glass, sizes or floating. The tab bar is a `.safeAreaInset(edge: .top)` above each editor
pane (above the missing-file and changed-on-disk banners), the format bar a `.safeAreaInset(edge: .bottom)` on `.bar`
material, the preview toolbar a `.safeAreaInset(edge: .top)` above the preview. Content never scrolls under them, so
there are no scroll insets: editor jumps, typewriter scrolling (centres in the visible area), Focus Mode anchoring and
the preview's visible-page maths use the plain visible rect.
The banners are a `Label` with a warning symbol, default buttons (the safe choice is the default action) and a `Divider`.
The sidebar navigator is a SwiftUI `TabView`; Symbols and References are format-bar popovers.

## Tab bar controls
The bar is plain SwiftUI, nothing custom: a horizontal `ScrollView` of `HStack`s (scrolls the active tab into view), each
tab a `Toggle(...).toggleStyle(.button)` (on = the shown file) plus a borderless icon-only `xmark` Button (none on pinned
tabs); the label is the name (italic = preview), a pin glyph, and a "•" when unsaved. "+" is a borderless icon-only
`New Tab` button. No glass, fills, theme colours or colour-scheme override in the bar.
The closed split's second pane is `Color.clear`, not a hidden hosting view (which still answered accessibility hit tests).
