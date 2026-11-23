# 14f: Labels, references and TODOs

## What it does
- Jump to Definition: ⌘-click on a `<label>` or `@ref` in the editor, or Navigate > Jump to Definition (⌃⌘J) at the caret. Goes to the first `<label>` definition (selected, with the find flash); else the bibliography entry key in its .bib/.yml; else a beep and a popover "No definition for @x". With duplicate labels it goes to the first and says how many there are.
- Rename Label… (⌃⌘E): a sheet with the current name, a field with live validation, and a summary ("1 definition and 5 references in 3 files"). Applies one `project.edit(..., actionName: "Rename Label")` per file, name part only (`<`, `>`, `@` and supplements stay). A bibliography key with no label is renamed in its entry and in every `@key`.
- Issues tab: a "TODOs" section under the diagnostics ("No TODOs" when empty). Each row shows marker and text, and file:line; click reveals it with a flash.

## Decisions
- `LabelIndex` (TypoKit/LabelIndex.swift) is pure: it scans (file, text) pairs with `TypstSyntax.tokens`. `Project.labelIndex()` supplies the texts (open buffer wins, else disk) and builds off the main actor. Only `.ref` spans starting with `@` count; the name stops at the typst-syntax rule (trailing `.` and `:` stay prose). Comments, strings and raw are never `.label`/`.ref` tokens, so rename leaves them alone.
- A `<x>` right after `(`, `,` or `:` (`#cite(<k>)`, `link(<x>)`) is classified as a reference, not a definition.
- Bib keys come from text scans: BibTeX `@type{key,` (not comment/string/preamble), hayagriva a column-0 `key:` line.
- Rename validation: non-empty, letters/digits/`_-.:`, different from the current name, not an existing label or bib key.
- TODO: `.comment` tokens containing the case-sensitive words TODO, FIXME, XXX. The range runs from the marker to the end of that comment line; the text after it is trimmed (leading `:` too). `Project.todos(cache:)` re-parses only files whose text changed.
- The sheet is an `NSWindow` sheet hosting SwiftUI (no ProjectView state needed); the "no definition" note is a popover at the caret.

## Limits
- The TODO list refreshes 0.6 s after a file-tree change or a compile status change (a compile follows every edit); there is no per-edit counter on Project.
- Menu items are enabled whenever a .typ file is shown; off a label/ref they beep, because the caret is not observable by menus.
- `label("x")` string forms are indexed (a definition when inserted in markup as `#label("x")`, otherwise a reference, e.g. `ref(label("x"))`, `#show label("x"):`). `ref("x")` is a Typst type error and is not indexed. Strings with a backslash, and `mylabel("x")`, are skipped.
- TODO, FIXME and XXX inside comments are drawn bold orange (`SyntaxTag.todo`, added in `Highlighter.recolor` from the same regex as the list; TOML/BibTeX files get none).
- The "Navigate" menu is created by ReferenceCommands; merge with any other lane's Navigate menu.

## Tests (LabelIndexTests.swift, 10; SyntaxTests, StructuredTests)
Definitions/refs with supplements, comments, strings, raw ignored; bib keys (.bib, .yml); target and duplicate count; validation; rename across files incl. a closed file and undo-safe edits; bib key rename; TODO scan (comments only, block comments, several); project TODO scan with open text and cache.
`label("x")` forms (reference vs `#label` definition, rename); TODO highlighting (comments only, TOML none) and incremental recolor over typing/splitting a marker.
