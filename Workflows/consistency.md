---
name: consistency
description: Find words, abbreviations, numbers and units written in more than one way, and make them consistent.
argument-hint: "[terms to check, or a file]"
---

# /consistency

Goal: every term in the document is written one way. Typical cases:

- spelling variants: E-Mail / Email / e-mail, Online / online, Datensatz / Daten-Satz
- abbreviations: ML / ml / Ml, PDF / pdf, z. B. / z.B. / zB
- units and numbers: 5 mL / 5ml / 5 ml, 10 % / 10%, 1.000 / 1000 / 1,000, a thin space or none
- capitalisation in headings: all heading words capitalised or sentence case, not both
- names: the same person, product or method spelled the same way
- abbreviations explained at their first use and only there

Anything the user wrote after `/consistency` narrows the check, such as a list of terms or a file. Without it, check the whole project.

## Steps

1. `list_files`, then `read_file` each `.typ` file the document includes. Ignore code blocks, raw text, URLs, file paths and labels (`<…>`, `@…`).
2. Collect the variants. For each group, use `search_project` to count every spelling. Searching is case-insensitive, so read the lines to tell `ML` from `ml`.
3. For each group, choose the form to keep:
   - a form the document defines, such as "Machine Learning (ML)"
   - otherwise the form the document's language and field use, such as `E-Mail` in German or `email` in English
   - otherwise the most frequent form
   If two forms are both reasonable and about equally common, don't choose. Ask.
4. Change the other spellings to the chosen form. Change only the term, never the sentence around it. Keep quotes, titles of cited works and code exactly as written.
5. `compile` at the end to make sure nothing broke.

## Report

A table, one row per group:

| Term | Kept | Changed | Where |
|---|---|---|---|

Then, separately, the groups you did not decide, each with its forms and counts, so the user can choose.

If everything was already consistent, say so in one line.
