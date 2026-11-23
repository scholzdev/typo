# Typo – Features

Stand: 23.11.2026. Nativer Typst-Editor für macOS (Swift 6, SwiftUI + AppKit/TextKit 2, Typst-Engine über eine Rust-Bridge).

## Fenster und Layout (Xcode-Stil)

- Toolbar wie Xcode: Navigator- und Assistant-Umschalter neben den Ampelknöpfen. Sie tauschen nur den Inhalt der Seitenleiste, der Editor bleibt stehen.
- Scheme-Kapsel in der Toolbar mit Hauptdatei und Exportziel.
- Umschalter für Vorschau und Inspector.
- Navigator als Liquid-Glass-TabView mit Slide-to-Select: Files, Search, Outline, Issues (mit Badge), Changes. VoiceOver liest die Tab-Namen.
- Dateibaum wie Xcode mit Filter-Leiste und „Open in New Tab“.
- Editor-Tabs wie Xcode: gleich breite Tabs, Schließen-Knopf beim Hover, Pinnen. Die Tab-Leiste erscheint erst ab zwei Tabs.
- Jump Bar mit farbigen Icons und Menüs.
- Inspector als rechte Spalte (File, Selection, …). Er zeigt Figure, Tabelle, Farbe, Label oder Funktionsaufruf unter dem Caret.
- Untere Leiste nur mit Issues, ohne Compile-Log.
- Split Editor und Fokus-Modus.

## Editor

- TextKit-2-Editor mit Syntax-Highlighting.
- Vervollständigung:
  - scope-aware über die Typst-Engine (Rust): Variablen, Funktionen aus Imports, Built-ins, Labels;
  - Labels und Bib-Keys nur, wenn sie erreichbar sind;
  - `#names` aus anderen Dateien mit Auto-Import.
- Snippets.
- Multi-Cursor mit Blinken (⌘D, ⌃⌘G, ⌃⇧↑/↓).
- Vim-Modus mit Mode-Kapsel im Xcode-Stil und Tasten-Hinweisen.
- Minimap mit Scroller rechts daneben.
- Sticky Headings (Code-Struktur-Kopfzeilen).
- Scope Guides, Rainbow Brackets, Klammer-Hervorhebung.
- Markieren gleicher Symbole mit einstellbarer Verzögerung.
- Inlay Hints.
- Farb-Swatches direkt neben `rgb(...)` und Co. Ein Klick öffnet einen Farbwähler als Popover neben der Zeile:
  - Zahlen und Hex-Wert sind editierbar;
  - Farbrad oder Schieberegler, einstellbar.
- Rechtschreibprüfung in der Sprache aus `#set text(lang:)`, ohne rote Unterstreichung in Mathe.
- Formatieren (typstyle) mit Zeilenbreite und Hilfslinie, optional beim Speichern oder beim Vervollständigen.
- Zeilenumbruch mit Einrückung, Overscroll, animierter Caret, Schreibmaschinen-Scrollen im Fokus-Modus.
- Lint-Hinweise und Diagnosen inline, abschaltbar.
- Quick Fixes, Jump to Definition, Find References, Rename Symbol, Go Back/Forward.
- Wortzählung, die nur deinen Text zählt, nicht den von Typst erzeugten, auch über Includes.

## Falten

- Falten von Überschriften, Klammern, Figures, Tabellen, Mathe, Raw-Blöcken, Kommentaren und Listen.
- Fold-Ribbon mit verschachtelten Kapseln, `{ ··· }`-Badge und Pfeil-Zacken.
- Animation nach Xcodes Prinzip:
  - ein Platzhalter im echten Layout, Papierfaltung als Snapshot;
  - der Text darunter fließt in jedem Frame nach;
  - ein Display-Link mit bis zu 120 Hz.
- Animationsdauer einstellbar (Editing › Display).
- Fold/Unfold Section und Fold/Unfold All im View-Menü.

## Assistant (KI)

- Anbieter: On-Device (Apple Intelligence), OpenRouter, OpenCode Zen, OpenCode Go und weitere OpenAI- bzw. Anthropic-kompatible Anbieter. API-Keys liegen nur im Schlüsselbund.
- Nichts wird gesendet, bevor du dem jeweiligen Anbieter zugestimmt hast.
- Fragen werden beantwortet, ohne etwas zu ändern (On-Device-Klassifizierer).
- Web-Suche.
- Rechte-Übersicht („darf ich x, darf ich y“): Dateien ändern oder anlegen, Vorschau ansehen, Projekt lesen, suchen, Diagnosen.
- Tools:
  - `typst_docs` mit kuratiertem Doku-Index;
  - Projekt lesen und durchsuchen;
  - `view_preview` und `compile`;
  - On-Device- und Gemini-Tools.
- Änderungen im Xcode-Stil: sofort angewendet, mit Datei-Header und Code-Block, „N Changes in M Files“, Revert-Leiste und Glow.
- Inline-Diff und Rainbow-Ribbon für KI-Änderungen im Gutter.
- Konversationsliste in der Seitenleiste.

## Tabellen-Editor

- Visueller Editor für `table(...)` und `grid(...)` (Format › Edit Table…, Rechtsklick oder Inspector).
- Raster wie in Numbers:
  - Spaltenleiste A, B, C… und Zeilennummern, Header-Zeile H;
  - Header, Leiste und Gutter bleiben beim Scrollen stehen.
- Zellen werden von Typst selbst gerendert: Mathe, Fett und Kursiv, aufgelöste Verweise, deine `#set`-Regeln. Markup erscheint nur beim Bearbeiten.
- Tastatur wie in einer Tabellenkalkulation:
  - Pfeile, Shift-Pfeile, Return, Tab, Esc;
  - Tippen ersetzt den Inhalt;
  - ⌘C/⌘V/⌘X, ⌘A, ⌘B/⌘I, Undo/Redo.
- Einfügen von TSV/CSV, auch aus Numbers und Excel. Die Tabelle wächst dabei mit.
- Zeilen und Spalten einfügen, löschen, duplizieren und verschieben (auch per Drag). Backspace auf eine ganze markierte Zeile oder Spalte löscht sie.
- Zellen verbinden und trennen (`table.cell(colspan:, rowspan:)`).
- Formatleiste:
  - horizontale und vertikale Ausrichtung pro Spalte;
  - Fett, Kursiv;
  - Stilvorlagen: Plain, Grid, Header Line, Booktabs, Striped;
  - Einfügen-Menü.
- Spaltenbreite per Ziehen (`fr` oder `pt`) oder über das Spaltenmenü (Auto, 1fr, 2fr, fest).
- Felder für Figure-Caption, Label und Placement.
- ✨ Intelligence-Popover:
  - Auftrag in eigenen Worten oder per Vorschlag: Sortieren, Summenzeile, Transponieren, Leere Zellen füllen, Übersetzen, Großschreibung, Beispieldaten, Zahlen formatieren;
  - Anbieter wählbar;
  - Ergebnis als ein einziger Undo-Schritt mit Zusammenfassung;
  - Zahlen in Mathe-Modus.
- Ein einziger, rückgängig machbarer Edit im Dokument bei „Done“. Fehlende Imports werden ergänzt.
- Fenstergröße wird gemerkt. VoiceOver-Unterstützung für das Raster.
- Zellen-Vervollständigung mit Engine-Unterstützung.

## Bibliografie

- BibTeX-Editor in SwiftUI mit Feldern und „More Fields“ sowie Prüfung der Pflichtfelder.
- Zitat einfügen (⇧⌘C).

## Packages

- Universe-Browser mit Detailansicht pro Package.
- Lokaler Packages-Ordner (`@local` und eigene Namespaces).
- Index der `@preview`-Packages mit Offline-Cache.

## Vorschau und Export

- Live-Vorschau mit Klick auf eine Stelle, die zur Quelle springt, Zoom, Fit Width/Page, zwei Seiten, Seitenminiaturen und dunklen Seiten.
- Präsentation im Vollbild und mit Presenter View.
- Export als PDF, PDF/A und PDF/UA-1 (barrierefrei), PNG und SVG.

## Projekt und Dateien

- Projekte, zuletzt geöffnete Projekte, Willkommensfenster, Vorlagen.
- Autosave, Snapshots (lokale Historie), Kodierung und Zeilenenden, Aufräumen von Leerzeichen.
- Git: Änderungen im Gutter, Changes-Navigator, Pull, Branches, Accounts.
- Live-Vorschau während des Tippens oder erst beim Speichern (einstellbar).

## Einstellungen

- Kopfzeile in der Titelleiste wie bei Xcode mit Zurück/Vor und Titel. Die Einstellungen öffnen auf General.
- General:
  - offene Projekte wiederherstellen;
  - Dateiendungen im Dateibaum;
  - Zeilenzahl in Find- und Issue-Navigator;
  - Issues inline anzeigen oder nicht;
  - Live-Vorschau beim Tippen oder beim Speichern;
  - Einstellungen exportieren und importieren;
  - Einstellungen zurücksetzen.
- Appearance: Theme, Schrift, Stile, Cursor, Hell/Dunkel, gedimmte Split-Panes.
- Intelligence: Anbieter, Modelle, Keys, Rechte.
- Navigation, Editing (Display, Completion, Indentation, Dateien), Snippets, Packages, Source Control, Components.
- Shortcuts wie in Xcode:
  - Shortcut-Sets (Default, eigene Sets duplizieren, umbenennen, löschen);
  - „Adapt to current keyboard“;
  - Filter All/Menu/Text/Customized/Conflicts;
  - Aufnahme per Doppelklick.
- Segmentierte Kapsel-Controls, Unterseiten behalten die Kopfzeile, kein Fokusring in der Seitenleiste.

## Bekannte Einschränkungen

- Fehler beim PDF/UA-1-Export haben oft keine Zeilenangabe; Typst liefert dafür keine Position.

## Bewusst nicht geplant (vorerst)

iCloud-Sync, Live-Kollaboration, Zotero-Anbindung, PDF-Vergleich, Spotlight-Indexierung, HTML-Export.
