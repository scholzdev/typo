# 14k Equation hover

Hovering a math equation (`$x^2$`, block `$ ... $`) shows it rendered at the top of the hover card, exactly as the
compiled document draws it (user macros, fonts, numbering). Diagnostics stay below the image; typst-ide's tooltip (the `symbol(...)` listing for `integral`) is dropped
whenever there is an image (`Project.hover`), so the card shows only the formula.

## How
- Bridge `tb_world_equation_image(world, path, cursor16, pixel_per_pt, ...)` finds the `Equation` node around the
  cursor in the file's overlay text and returns an opaque RGBA crop plus the equation's UTF-16 range and the size in points.
- The crop comes from `last_doc`. Frames are walked with accumulated group transforms; everything between the
  `Tag::Start` of an element whose span is the equation node and its matching `Tag::End` belongs to it, so content
  from `#let` macros is included. Text boxes use the font ascender/descender at the item size, shapes their
  stroked bbox, images their size. Padding 3 pt.
- Rendering: a hard frame of the box size holding the page frame shifted by minus the box origin, rendered with
  `typst_render` and the page's solid fill (white when the fill is none, transparent or a gradient, so black math
  stays readable on the dark card). Wider than 1600 px: the scale is reduced.
- Swift: the image rides on the existing hover request (`HoverRequest.pixelsPerPoint`, superseded like any hover);
  `HoverInfo.equation` is `EquationImage(image, size)`. When present, `HoverInfo.range` is the whole equation, so the
  card stays while the pointer is anywhere inside the formula. The app asks for 1.5x the document size times the
  window's backing scale; the card shows the image at its point size (scaled down to the card width), rounded, hairline border.

## Freshness
The bridge records a hash of every overlay's text at each successful compile (`compiled_text`). An image is only
returned when the hovered file's current text hashes the same: after an edit the document's spans may point at the
wrong nodes, so the card shows only the normal tooltip until the recompile lands (and undoing back to the compiled text is fresh again).

## Several occurrences
An equation from a `#let` or an included file appears several times. Each Start..End pair is its own cluster per
page (never merged across pages or occurrences). The cluster nearest `jump_from_cursor`'s first position for the cursor wins
(distance 0 inside its box, other pages excluded); without a jump point, the first cluster.

## Limits
- No image while the document has errors (no `last_doc` update) or when the file was edited since the last successful compile.
- Files not part of the compiled document show none.
- No cache: a crop is a few milliseconds and the pointer keeps the card without new requests.
- The crop is a rectangle of the page, so overlapping neighbouring content inside the padding shows too, as in the PDF.
- The number of a numbered block equation is included (the crop spans the whole row, hence the page width).

## Tests
`EquationHoverTests`: inline image and range, numbered block, macro, edited file, cursor outside math, repeated
equation not merged into a tall box, no symbol tooltip on an equation hover. PNGs of the first three go to `scratchpad/eqhover/`.
