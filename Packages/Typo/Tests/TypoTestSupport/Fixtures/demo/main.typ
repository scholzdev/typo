#set page(paper: "a4", margin: 2cm)
#set text(lang: "de")
#set heading(numbering: "1.")

= Einleitung
Dies ist ein Testdokument für den Editor. Die Formel $E = m c^2$ steht im Text.

$ integral_0^1 x^2 dif x = 1/3 $

#include "kapitel.typ"

We can all derive from one or another

#let x = 1 + 2
#x
#text(fill: red)[Hallo]
#figure(
  table(
    columns: 5,
    table.header([], [], [], [], []),
    [], [], [], [], [],
    [], [], [], [], [],
  ),
  caption: [],
)