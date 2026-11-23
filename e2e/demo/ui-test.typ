#set page(paper: "a4", margin: 2cm, numbering: "1")
#set text(lang: "de")
#set heading(numbering: "1.1")
#set math.equation(numbering: "(1)")

= Einleitung <intro>
Dieses Dokument dient zum Testen der Oberfläche: Gliederung, Wortzahl, Literatur, Symbole und Vorschau.
Wie in @knuth84 beschrieben, ist gute Typografie unsichtbar. Siehe auch @gleichung.

$ sum_(k=1)^n k = (n (n+1)) / 2 $ <gleichung>

#figure(image("logo.png", width: 30%), caption: [Ein kleines Bild.])

== Unterabschnitt
#lorem(300)

= Hauptteil
#lorem(400)

== Tabelle
#table(
  columns: 3,
  table.header([Name], [Alter], [Ort]),
  [Anna], [31], [Bremen],
  [Ben], [27], [Hamburg],
)

== Formeln
Die Formel $alpha + beta = gamma$ steht im Text, wie in @intro angekündigt.

#lorem(400)

= Schluss
#lorem(200)

#bibliography("refs.bib")
