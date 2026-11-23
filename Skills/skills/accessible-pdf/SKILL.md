---
name: accessible-pdf
description: Make a Typst document produce an accessible PDF (PDF/UA): document metadata, language, heading order, alt text, table headers. Use when the user asks about accessibility, PDF/UA, archiving or screen readers.
---

# Accessible PDF

Typo exports PDF/UA-1 and checks accessibility on export. Get the source right:

- Set metadata and language: `#set document(title: [...], author: "…")` and `#set text(lang: "de")` (the document's real language).
- Headings in order: no jump from level 1 to level 3. Use real `= Heading` markup, not bold text.
- Every image and figure that carries meaning gets alt text: `#image("plot.png", alt: "…")`. Purely decorative images are marked as artifacts per `typst_docs`.
- Tables use `table.header(...)` for header rows.
- Don't convey meaning by color alone; keep enough contrast.
- Links get meaningful text instead of a bare URL where possible.
- After editing, `get_diagnostics`; Typo reports accessibility problems there when the check is on. List what you fixed and what still needs the user (for example, writing alt text needs their knowledge of the image).
