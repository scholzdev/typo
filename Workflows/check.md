---
name: check
description: Make the project compile cleanly and look right on every page.
argument-hint: "[file or page range to focus on]"
---

# /check

Goal: the document compiles without errors or warnings, and no page shows a layout problem. Finish with a short report.

If the user named a file or pages after `/check`, look at those first, then the rest.

## 1. Compile

1. Call `compile`. It waits for the current build and returns every error and warning.
2. Fix errors first, in the order reported: one root error often causes the later ones. For each:
   - `read_file` around the line, enough to see the whole call or block.
   - Fix the cause with the smallest edit. Don't reformat or rewrite parts that work.
   - Unsure about a function or parameter: `typst_docs`, never guess.
3. Call `compile` again after each round. Stop when it is clean or only problems are left that need the user (see below).
4. Then warnings. Fix those with a clear fix (an unused import, a deprecated name). Leave the rest in the report.

## 2. Look at every page

1. `view_preview` with page 1. Its answer says how many pages there are. Look at each page in turn.
2. On each page look for:
   - text or figures running into the margin or off the page
   - an empty or nearly empty page, or a heading alone at the bottom of a page
   - `??` or a visible label instead of a reference or citation
   - a missing image (a box or an error placeholder)
   - a table split so its header row is missing on the next page
   - overlapping elements
3. Fix what has a clear cause in the source, then `compile` and look at that page again.
4. For a long document (more than about 30 pages), look at every page with a figure, a table or a new chapter, and sample the rest.

## Don't

- Don't change the wording of the text. /check is about the build and the layout.
- Don't delete content, images or citations to make an error go away.
- Don't guess a missing file, package version or bibliography entry. Report it.

## Report

At most 10 lines:

- **Fixed:** one line per fix, as `file:line` and what was wrong.
- **For you:** what needs the user, such as a missing image or an unknown citation key, with where it is.
- **Pages:** how many, and whether all of them look right.

If everything was already clean, say so in one line.
