---
name: fix-compile-errors
description: Find and fix Typst compile errors and warnings in the open Typo project. Use when the document doesn't compile, the user mentions an error, or diagnostics show problems.
---

# Fix compile errors

1. Call `get_diagnostics` to get every error and warning with file, line and message. Work on errors first, in the order the compiler reports them; one root error often causes the later ones.
2. For each error, `read_file` around the reported line. Read enough context to see the enclosing function call or block.
3. Find the cause, not just the symptom:
   - `unknown variable` / `unknown function`: a missing `#import`, a typo, or a binding defined after its use or in another file.
   - `expected X, found Y`: a wrong argument type; check the parameter with `typst_docs`.
   - `unclosed delimiter`: count brackets in the block the error points into; the real gap is often earlier.
   - `file not found`: compare the path with `list_files`; paths are relative to the file that names them.
   - `label does not exist`: search with `search_project` for the label; it may be misspelled or in a file that isn't included.
   - `package not found` / version errors: see the packages skill.
4. Make the smallest change that fixes the cause. Don't rewrite working parts or reformat the file.
5. Call `get_diagnostics` again. Repeat until there are no errors you can fix.
6. Answer with what was wrong and what you changed, one line per error. If something needs the user's decision (a missing image, an unknown package version), say so instead of guessing.
