# Typo features

As of 24 November 2026. Native Typst editor for macOS (Swift 6, SwiftUI + AppKit/TextKit 2, Typst engine through a Rust bridge).

## Window and layout (Xcode style)

- Toolbar like Xcode: navigator and assistant toggles next to the traffic lights. They only swap the sidebar content. The editor stays in place.
- Scheme capsule in the toolbar with the main file and export target.
- Toggles for preview and inspector.
- Navigator as a Liquid Glass TabView with slide-to-select: Files, Search, Outline, Issues (with badge), Changes. VoiceOver reads the tab names.
- File tree like Xcode with filter bar and "Open in New Tab".
- Editor tabs like Xcode: equal-width tabs, close button on hover, pinning. The tab bar appears only from two tabs.
- Jump bar with colored icons and menus.
- Inspector as a right column (File, Selection, …). It shows the figure, table, color, label or function call under the caret.
- Bottom bar with Issues only, no compile log.
- Split editor and focus mode.

## Editor

- TextKit 2 editor with syntax highlighting.
- Completion:
  - scope-aware through the Typst engine (Rust): variables, functions from imports, built-ins, labels;
  - labels and bib keys only when they are reachable;
  - `#names` from other files with auto-import.
- Snippets.
- Multi-cursor with blinking (⌘D, ⌃⌘G, ⌃⇧↑/↓).
- Vim mode with an Xcode-style mode capsule and key hints.
- Minimap with the scroller next to it on the right.
- Sticky headings (code structure headers).
- Scope guides, rainbow brackets, bracket highlighting.
- Highlighting of matching symbols with an adjustable delay.
- Inlay hints.
- Color swatches right next to `rgb(...)` and similar. One click opens a color picker as a popover next to the line:
  - numbers and hex value are editable;
  - color wheel or sliders, configurable.
- Spell checking in the language from `#set text(lang:)`, with no red underline in math.
- Formatting (typstyle) with line width and guide line, optionally on save or on completion.
- Line wrapping with indentation, overscroll, animated caret, typewriter scrolling in focus mode.
- Lint hints and diagnostics inline, can be turned off.
- Quick fixes, Jump to Definition, Find References, Rename Symbol, Go Back/Forward.
- Word count that counts only your text, not the text Typst generates, also across includes.

## Folding

- Folding of headings, brackets, figures, tables, math, raw blocks, comments and lists.
- Fold ribbon with nested capsules, `{ ··· }` badge and arrow tips.
- Animation based on Xcode's approach:
  - a placeholder in the real layout, paper fold as a snapshot;
  - the text below reflows in every frame;
  - a display link at up to 120 Hz.
- Adjustable animation duration (Editing › Display).
- Fold/Unfold Section and Fold/Unfold All in the View menu.

## Assistant (AI)

- Providers: on-device (Apple Intelligence), OpenRouter, OpenCode Zen, OpenCode Go and other OpenAI- or Anthropic-compatible providers. API keys are stored only in the keychain.
- Nothing is sent until you have agreed to the provider in question.
- Questions are answered without changing anything (on-device classifier).
- Web search.
- Permissions overview ("may I do x, may I do y"): change or create files, view the preview, read the project, search, diagnostics.
- Tools:
  - `typst_docs` with a curated docs index;
  - read and search the project;
  - `view_preview` and `compile`;
  - on-device and Gemini tools.
- Changes in Xcode style: applied immediately, with file header and code block, "N Changes in M Files", revert bar and glow.
- Inline diff and rainbow ribbon for AI changes in the gutter.
- Conversation list in the sidebar.

## Table editor

- Visual editor for `table(...)` and `grid(...)` (Format › Edit Table…, right-click or inspector).
- Grid like in Numbers:
  - column bar A, B, C… and row numbers, header row H;
  - header, bar and gutter stay in place while scrolling.
- Cells are rendered by Typst itself: math, bold and italic, resolved references, your `#set` rules. Markup appears only while editing.
- Keyboard like in a spreadsheet:
  - arrows, Shift-arrows, Return, Tab, Esc;
  - typing replaces the content;
  - ⌘C/⌘V/⌘X, ⌘A, ⌘B/⌘I, Undo/Redo.
- Pasting TSV/CSV, also from Numbers and Excel. The table grows to fit.
- Insert, delete, duplicate and move rows and columns (also by dragging). Backspace on a fully selected row or column deletes it.
- Merge and split cells (`table.cell(colspan:, rowspan:)`).
- Format bar:
  - horizontal and vertical alignment per column;
  - bold, italic;
  - style presets: Plain, Grid, Header Line, Booktabs, Striped;
  - Insert menu.
- Column width by dragging (`fr` or `pt`) or through the column menu (Auto, 1fr, 2fr, fixed).
- Fields for figure caption, label and placement.
- ✨ Intelligence popover:
  - task in your own words or from a suggestion: Sort, Total row, Transpose, Fill empty cells, Translate, Capitalization, Sample data, Format numbers;
  - choice of provider;
  - result as a single undo step with a summary;
  - numbers in math mode.
- A single undoable edit in the document on "Done". Missing imports are added.
- Window size is remembered. VoiceOver support for the grid.
- Cell completion with engine support.

## Bibliography

- BibTeX editor in SwiftUI with fields and "More Fields", plus a check of required fields.
- Insert citation (⇧⌘C).
- Add Reference: looks up a DOI, arXiv ID or ISBN and appends the entry to a .bib file of the project.
- Zotero sync (File › Connect Zotero…): fills a .bib file of the project from the local Zotero app or a Zotero account and keeps it in sync.

## Packages

- Universe browser with a detail view per package.
- Local packages folder (`@local` and custom namespaces).
- Index of `@preview` packages with offline cache.

## Preview and export

- Live preview with click-to-source (click a spot to jump to the source), zoom, Fit Width/Page, two pages, page thumbnails and dark pages.
- Presentation in full screen and with Presenter View.
- Export as PDF, PDF/A and PDF/UA-1 (accessible), PNG and SVG.
- Export a page range as PDF ("1-3, 7, 9-"); PDF/UA-1 always exports every page.

## Project and files

- Projects, recent projects, welcome window, templates.
- Autosave, snapshots (local history), encoding and line endings, whitespace cleanup.
- Git: changes in the gutter, Changes navigator, pull, branches, accounts.
- Live preview while typing or only on save (configurable).

## Settings

- Header bar in the title bar like Xcode with back/forward and title. Settings open on General.
- General:
  - restore open projects;
  - file extensions in the file tree;
  - line count in the Find and Issue navigators;
  - show issues inline or not;
  - live preview while typing or on save;
  - export and import settings;
  - reset settings.
- Appearance: theme, font, styles, cursor, light/dark, dimmed split panes.
- Intelligence: providers, models, keys, permissions.
- Navigation, Editing (Display, Completion, Indentation, Files), Snippets, Packages, Source Control, Components.
- Shortcuts like in Xcode:
  - shortcut sets (Default, duplicate, rename and delete your own sets);
  - "Adapt to current keyboard";
  - filter All/Menu/Text/Customized/Conflicts;
  - recording by double-click.
- Segmented capsule controls, subpages keep the header bar, no focus ring in the sidebar.

## Known limitations

- Errors during PDF/UA-1 export often have no line number. Typst gives no position for them.

## Intentionally not planned (for now)

iCloud sync, live collaboration, PDF comparison, Spotlight indexing, HTML export.
