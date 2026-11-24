---
name: submit
description: Check the project before it is handed in or published, as a checklist.
argument-hint: "[requirements, e.g. max 12 pages, APA, PDF/UA]"
---

# /submit

Goal: tell the user whether the document is ready to hand in, and fix what is safe to fix. The user exports the PDF themselves with File › Export.

Anything the user wrote after `/submit` is a requirement, such as a page limit, a citation style or PDF/UA. Check against it. If the project has a file with requirements, such as `README`, `requirements.md` or comments in the main file, read that too.

## Checks

Do them in this order. Each one is pass, fixed or open.

1. **Builds:** `compile` shows no errors. If not, fix them as /check does and continue.
2. **Leftovers:** `search_project` for `TODO`, `FIXME`, `XXX`, `lorem`, `??` and `[citation needed]`. Draft-only things also count, such as a `draft` watermark or highlighted text.
3. **References:** no `??` in the output. Every `@label` resolves. Every citation key exists in the bibliography. The bibliography is in the document if there are citations.
4. **Length:** the page count from `view_preview`, measured against the user's limit if one was given. Count only pages the requirement counts, if it says so (for example without the title page or the appendix).
5. **Metadata:** `#set document(title: …, author: …)` is set and correct. `#set text(lang: …)` matches the document's language.
6. **Structure:** heading levels don't skip (no `=` straight to `===`). There is a title. The outline, if there is one, matches the headings.
7. **Figures and tables:** every image that carries meaning has `alt:` text. Every figure is referenced in the text. Tables use `table.header(...)`.
8. **Fonts:** every font named in `#set text(font: …)` is installed. `compile` warns about missing fonts.
9. **Accessibility:** if PDF/UA was asked for or the project's export uses it, the checks above for metadata, headings, alt text and table headers all pass. Typo reports more problems in `get_diagnostics` when its accessibility check is on.
10. **Look:** `view_preview` of the first page, the last page and one page per chapter. No layout problems as listed in /check.

## Fixing

- Fix mechanical problems yourself: a skipped heading level, missing `table.header`, missing `lang`, a broken label.
- Don't write alt text, a title, an abstract or other content yourself. Name the place and ask the user. You don't know what the image shows to a reader.
- Never remove content or citations to meet a page limit. Report how far over it is.

## Report

A checklist, one line each, in the order above:

- ✅ passed
- 🔧 fixed: what changed, as `file:line`
- ⚠️ open: what the user must do, and where

End with one line: **Ready to hand in** or **Not ready: N open points**.
