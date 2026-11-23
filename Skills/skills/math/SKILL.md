---
name: math
description: Write Typst math correctly (inline and display equations, numbering, alignment, symbols). Use when the user asks for formulas or converts LaTeX math to Typst.
---

# Math

- Inline: `$x^2$`. Display: put spaces inside the dollars, `$ x^2 $`, on its own line.
- Typst is not LaTeX: `frac(a, b)` or `a / b`, `sqrt(x)`, `sum_(i=1)^n`, `integral_0^1`, `vec(1, 2)`, `mat(1, 2; 3, 4)`, `cases(…)`. Greek letters and symbols are plain names: `alpha`, `arrow.r`, `<=`, `in`, `RR`.
- Multi-letter words are variables only when defined; write text as `"text"` and upright operators with `op("rank")`.
- Align with `&` and break lines with `\`.
- Number equations with `#set math.equation(numbering: "(1)")` and reference them by label: `$ E = m c^2 $ <einstein>`, then `@einstein`.
- When converting LaTeX, translate commands rather than copying backslashes; check unknown names with `typst_docs`.
- Check the result with `get_diagnostics` and `view_preview`.
