#set document(title: "Typo", author: "Typo")
#set page(paper: "a4", margin: 2.2cm, numbering: "1")
#set text(font: "Libertinus Serif", size: 11pt)
#set text(lang: "en")
#set par(justify: true)
#set heading(numbering: "1.")
#set math.equation(numbering: "(1)")

#let accent = rgb("#5B54E8")

#grid(
  columns: (auto, 1fr),
  column-gutter: 14pt,
  align: horizon,
  image("logo.png", width: 1.6cm),
  [
    #text(size: 22pt, weight: "bold")[Typo] \
    #text(fill: accent)[Typst, at home on the Mac]
  ],
)
#line(length: 100%, stroke: 0.6pt + accent)

*This page was written in Typo.*
Source on the left, live preview on the right.
Click any line of this page to jump to its source.

= Write without friction <write>
Completion comes from the Typst engine itself:
variables, imported functions, labels and
bibliography keys that are actually in scope.
Spelling is checked in the language of
`#set text(lang: ..)`, and never inside math.

Math renders as you type, with a number you can
point to from anywhere:

$ sum_(k=1)^n k = (n (n + 1)) / 2 $ <gauss>

Type `@ga` and Typo completes the label: @gauss.

= Find anything <find>
Press ⇧⌘O to open any file, heading or label,
⌘L to jump to a line, and ⌥⌘B to bookmark one.
The outline reorders whole chapters by drag and
drop, and headings fold away with a paper-like
animation.

#include "kapitel.typ"

= Tables like Numbers <tables>
Right-click a table and choose Edit Table.
Cells are rendered by Typst, paste from Numbers
or Excel just works, and Done writes one undoable
edit back into your source.

#figure(
  table(
    columns: 3,
    align: (left, left, center),
    inset: (x: 10pt, y: 7pt),
    stroke: none,
    fill: (_, row) => if row == 0 {
      accent.lighten(80%)
    } else if calc.even(row) { luma(247) },
    table.header([*Action*], [*Menu*], [*Shortcut*]),
    table.hline(stroke: 0.8pt + accent),
    [Open Quickly], [Navigate], [⇧⌘O],
    [Go to Line], [Navigate], [⌘L],
    [Toggle Bookmark], [Navigate], [⌥⌘B],
    [Move Section Up], [Format], [⌃⌥↑],
    [Fold Section], [View], [⌥⌘←],
  ),
  caption: [Made in Typo's table editor.],
) <shortcuts>

= Cite with confidence <cite>
The bibliography is a form, not a puzzle.
Paste a DOI, arXiv ID or ISBN and Typo fills in
the entry, then ⇧⌘C inserts the citation
@madje2022.

= Ship it <ship>
Export to PDF, PDF/A, accessible PDF/UA-1, PNG
or SVG. The accessibility check flags missing
alt text before you send anything off.

#figure(
  image("logo.png", width: 22%),
  alt: "The Typo app icon",
  caption: [The Typo icon, made in Icon Composer.],
) <img:logo>

#bibliography("refs.bib")
