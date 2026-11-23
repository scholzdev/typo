---
name: tables
description: Create and edit Typst tables and grids so they stay editable in Typo's table editor. Use when the user asks for a table, wants data laid out in rows and columns, or edits an existing #table.
---

# Tables

- Use `#table(columns: …, …cells)` for data and `#grid` for layout. Wrap a captioned table in `#figure(table(…), caption: [...]) <label>` so it can be referenced.
- Keep the cells as plain content in reading order, one cell per argument. Typo's table editor parses this form; deeply computed tables (cells built in loops) still compile but can't be edited visually.
- Put the header in `table.header(...)` so it repeats on page breaks and is tagged as a header in accessible PDFs.
- Style once, not per cell: `stroke`, `fill: (x, y) => if y == 0 { … }`, `align`, `inset`. Use `table.hline()` for rules.
- Column sizes: `auto` fits the content, `1fr` shares the rest, fixed lengths only when needed.
- For numbers, align right or on the decimal point and keep the same precision in a column.
- After editing, `view_preview` the page to check widths and breaks.
