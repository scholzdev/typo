---
name: citations
description: Add, check and fix citations and bibliographies in Typst (bibliography files, @keys, citation styles). Use when the user asks about sources, references, a .bib or .yml bibliography, or citation styles.
---

# Citations

- Find the bibliography: `search_project` for `bibliography(`. Typst reads BibTeX (`.bib`) and Hayagriva (`.yml`) files.
- Cite with `@key` or `#cite(<key>)`; page and supplement: `@key[p. 12]`. Use `#cite(<key>, form: "prose")` for "Author (Year)".
- Check keys before you cite: `read_file` the bibliography and use only keys that exist. Never invent a source, a DOI or page numbers. If a source is missing, tell the user which one and offer an entry for them to verify.
- Styles: `#bibliography("refs.bib", style: "apa")`; other built-in names include "ieee", "chicago-author-date", "mla" and "harvard-cite-them-right". Check `typst_docs` for the full list; a `.csl` file path also works.
- Typo can keep a bibliography in sync with Zotero. Such a file is managed by Typo and read-only: don't edit it, add the source in Zotero instead and tell the user so.
- After changes, `get_diagnostics` reports unknown keys; fix them before you answer.
