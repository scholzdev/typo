# 14c Citations

## What it does
- **Add Reference…** (References popover in the format bar: footer button and the "No Bibliography" empty state). The sheet takes a DOI or ISBN,
  fetches it, previews title/authors/year/kind, lets you edit the key (checked for validity and uniqueness against every
  bibliography of the project), picks the target .bib, and optionally inserts the citation at the caret.
- **Insert Citation…** (Format, ⇧⌘C, enabled with a focused editor): a sheet that searches all bibliography entries with the
  References popover's filter (`BibEntry.matches`). Up/Down move, Return inserts, Esc cancels, ⌘/⇧-click selects several.
  Insertion uses `BibliographyFile.citations`: `@a @b` in markup, `cite(<a>), cite(<b>)` in code, space-joined in math.
- **`@` completion**: label items that are bibliography keys show "Authors (Year): Title" as detail
  (`Project.enrichedWithBibliography`, cached per `bibliographyRevision`).

## Core (`ReferenceLookup.swift`)
- `ReferenceID.parse`: bare DOI, `doi:`, doi.org / dx.doi.org URLs (percent-decoded); ISBN-10/13 with hyphens or spaces,
  checksum-validated. `ReferenceFetch` is injected; tests never touch the network.
- DOI: GET `https://doi.org/<doi>` with `Accept: application/x-bibtex; charset=utf-8`. ISBN: Open Library
  `api/books?bibkeys=ISBN:<isbn>&format=json&jscmd=data`, turned into a `@book` (authors "Last, First and …").
  User-Agent `Typo/0.1`, 20 s timeout. Errors: not found, offline, unreadable (each with a readable message).
- Key: the fetched key is kept if valid (`[A-Za-z_][A-Za-z0-9_:.-]*`) and unused; otherwise `<lastname><year>`
  (ASCII-folded, lowercase) plus a, b, c… The final entry must parse to exactly one entry with the bridge parser.
  ISBN entries always get the author-year key.
- Target: one .bib → it; several → the first named by a `bibliography("…")` string in a .typ file, else the user picks;
  none → `refs.bib` is created at the root (without selecting it) and `#bibliography("refs.bib")` is appended to the
  main file if the checkbox is on. Text changes go through `project.edit`, action name "Add Reference", one undo step per file.

## Limits
- A DOI answer is stored as delivered (Crossref returns one line per entry); no reformatting.
- Only `.bib` files are targets; hayagriva YAML projects get a new `refs.bib`.
- The completion cache follows `bibliographyRevision`; an external edit of a closed .bib is picked up on the next
  structural change (existing gap of the References tab).
- The picker is a sheet, not a popover.

## Tests (`ReferenceTests.swift`)
DOI/ISBN parsing table; stubbed DOI response (request headers, key kept, key rewrite on collision, invalid key replaced);
Open Library JSON to `@book`; fetch errors; target choice (one, several with `bibliography("x.bib")`, none → refs.bib
created and `#bibliography` appended); adding goes through the buffer and one undo restores it; citation join per mode;
completion detail "Donald E. Knuth (1984): The TeXbook" through the real engine.
