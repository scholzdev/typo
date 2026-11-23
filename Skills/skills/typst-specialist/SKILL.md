---
name: typst-specialist
description: Write and edit Typst documents idiomatically (markup, code mode, set and show rules, labels and references, functions). Use for any change to a .typ file in a Typo project.
---

# Typst specialist

The project is a Typst document opened in Typo. Typo compiles with Typst 0.15 and shows the PDF live, so every edit you make is visible right away.

## Before you edit

- Call `get_outline` to see the document's headings and labels, and `list_files` for its files. The entry file is the one `typst.toml` or the user names; usually `main.typ`.
- Read the file with `read_file` instead of guessing; the open buffer may hold unsaved text the disk doesn't have.
- When unsure how a function or parameter works, call `typst_docs` with the name. Do not rely on memory of LaTeX or older Typst versions.

## Writing Typst

- Markup is the default; `#` switches to code for one expression. Inside `{ }` or a function body you are already in code.
- Style with `set` rules (`#set text(lang: "de")`, `#set par(justify: true)`) near the top, and change how elements look with `show` rules (`#show heading.where(level: 1): set text(size: 16pt)`). Prefer one rule over repeating arguments.
- Put shared values in `#let` bindings and reuse them; keep colors and sizes in one place.
- Label targets with `<name>` right after the element and reference them with `@name`. Don't hard-code numbers like "Section 2".
- Split long documents with `#include "chapter.typ"`; share definitions with `#import "defs.typ": *`.
- Strings use double quotes; content uses brackets `[ ]`. Lengths need units (`2pt`, `1em`, `50%`).
- Comments: `//` and `/* */`. Typo shows `//` comments in the editor only.

## After you edit

- Call `get_diagnostics`. Fix every error you caused before you answer; mention warnings you left.
- Use `view_preview` when the change is visual (layout, tables, figures) and check the page it affects.
- Tell the user which file and which part you changed. Typo shows your edit as a diff the user can revert.
