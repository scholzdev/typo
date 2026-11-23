# 14b Export and writing progress

## Export (File ▸ Export)
- **PDF…** (⇧⌘E) and **PDF/A-2b for Archiving…** use `Project.exportPDF(standard:)` (`.plain`, `.pdfA2b`, `.pdfA3b`) over
  `tb_snapshot_export_pdf`. A failure returns the real typst-pdf error text (`ProjectError.exportFailed`), not the compile
  diagnostics. PDF/A also needs a creation date, so the bridge passes today's date as the PDF timestamp.
- **PNG Images…** / **SVG Images…** use `Project.exportPages(.png(ppi:) | .svg)`, one `Data` per page. PNG is encoded in
  Swift with ImageIO from the preview's `render` (pixelsPerPoint = ppi / 72, DPI written to the file); SVG is
  `tb_snapshot_svg` (typst-svg). Both wait for a compile that covers every edit (`settledSnapshot`, shared with the PDF).
- One page or a PDF: NSSavePanel. Several pages: NSOpenPanel for a folder (the sandbox grants no siblings of a saved file),
  files `<stem>-<n>.<ext>`, n zero-padded to the page count's width. If any target exists, one Replace / Cancel alert
  precedes any write. PNG resolution is an accessory popup (72, 150, 300 default, 600 ppi).
- Menu code: `App/ExportCommands.swift`. "Actual Size" (⌘0) is now "Fit Width", which is what zoom = 1 means.

## Writing progress
- `tb_snapshot_section_words` returns JSON `[{title, level, words, page}]` from the compiled document (so `#include`d
  chapters work): every heading in document order; each text item goes to the last heading at or before its (page, y);
  entry 0 (level 0, empty title) holds text before the first heading. Same segmentation as the total, so the sum equals
  `tb_snapshot_word_count` (tested). `Project.sectionWords` updates with `wordCount`, off the main actor.
- `WritingProgress` (pure; goal, first count of the calendar day) and `ProgressStore` (UserDefaults key
  `Typo.progress.<project id>`). Today is `total - first count seen today`, negative when text was deleted. The first
  count is recorded only once a count exists, so launching does not count the whole text as today's.
- The bottom bar count is a borderless button: "1,234 / 20,000 words" plus a ring with a goal, the selection label
  ("12 of 4,075 words") wins while text is selected. The popover (`App/ProgressPopover.swift`) has the goal field (empty =
  none), a progress bar, today's words and a table of level-1 chapters (deeper sections summed in, front matter only when
  it has words). A row reveals its heading by matching the outline on level, title and page.

## Limits
- Section words count headers and page numbers like the total, so a page number lands in the section on that page's footer.
- Headings that are not in a project file (from packages) are counted as sections but cannot be revealed.
- PNG at 600 ppi renders every page at full size in memory one at a time; large documents take a while.
- Tests: `ExportTests.swift` (PDF/A markers, PNG signature/size/DPI, SVG, section sums, include attribution, goal/day arithmetic).
