import Foundation

/// The Typst reference the assistant searches with `typst_docs`: the markup, the scripting syntax and the common functions,
/// each with signature, description and example. It is bundled text, so a lookup sends nothing anywhere.
public enum TypstDocs {
    public struct Entry: Equatable, Sendable {
        public var name: String
        public var signature: String
        public var about: String
        public var example: String
        /// Other words a question may use for it.
        var keywords: String

        /// The entry as Markdown.
        public var text: String {
            "**\(name)**: \(about)\n```typst\n\(signature)\n```\nExample:\n```typst\n\(example)\n```"
        }
    }

    /// The best entries for `query`, best first. Names weigh most, then keywords, then the description.
    public static func search(_ query: String, limit: Int = 5) -> [Entry] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#()"))
        let words = q.split { !($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_") }.map(String.init).filter { $0.count > 1 || $0 == "h" || $0 == "v" }
        guard !words.isEmpty else { return [] }
        func score(_ e: Entry) -> Int {
            let name = e.name.lowercased(), keys = e.keywords.lowercased(), about = e.about.lowercased()
            var total = name == q ? 100 : 0
            for w in words {
                if name == w { total += 60 } else if name.hasSuffix("." + w) || name.hasPrefix(w + ".") { total += 40 } else if name.contains(w) { total += 25 }
                if keys.split(separator: " ").contains(where: { $0 == w }) { total += 15 } else if keys.contains(w) { total += 6 }
                if about.contains(w) { total += 3 }
            }
            return total
        }
        var scored: [(entry: Entry, score: Int)] = []
        for entry in all {
            let s = score(entry)
            if s > 0 { scored.append((entry, s)) }
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.entry.name < $1.entry.name }
        return scored.prefix(limit).map { $0.entry }
    }

    static let all: [Entry] = rows.map { Entry(name: $0[0], signature: $0[1], about: $0[2], example: $0[3], keywords: $0.count > 4 ? $0[4] : "") }

    /// name, signature, description, example, keywords
    private static let rows: [[String]] = [
        // Markup and syntax
        ["markup", "= Heading\n*strong* _emphasis_ `raw` $math$\n- bullet\n+ numbered\n/ Term: description\n<label> @label\n#expr // comment", "Typst's markup: headings with =, strong with *, emphasis with _, lists with - and +, term lists with /, labels in <>, references with @, code after #.", "= Title\nSome *bold* and _italic_ text, see @intro.\n- one\n- two", "syntax bold italic list heading comment escape"],
        ["let", "#let name = value\n#let f(x, y: 1) = x + y", "Binds a value or defines a function. A function body is an expression or a [content block].", "#let accent = rgb(\"#3366cc\")\n#let note(body) = text(fill: accent, body)\n#note[Careful]", "variable function define binding scripting"],
        ["set rule", "#set function(argument: value)", "Sets default arguments of an element for everything after it (in the current scope).", "#set text(font: \"New Computer Modern\", size: 11pt)\n#set par(justify: true)", "set style default configure"],
        ["show rule", "#show selector: it => content\n#show: template", "Transforms how an element looks. The selector is an element, a text, a regex or a label; a plain `#show: f` applies a template.", "#show heading: it => text(fill: blue, it)\n#show \"Typst\": smallcaps", "show style transform template replace selector"],
        ["if", "#if condition { a } else if other { b } else { c }", "Conditional. In code the branches are blocks; in markup use [content].", "#if x > 3 [big] else [small]", "else conditional branch"],
        ["for", "#for item in array { }\n#for (key, value) in dictionary { }\n#while condition { }", "Loops over arrays, dictionaries, strings or ranges; the results of each iteration are joined.", "#for i in range(3) [Item #i \\ ]", "loop while iterate range"],
        ["import", "#import \"file.typ\": name1, name2\n#import \"@preview/pkg:1.0.0\": *\n#include \"chapter.typ\"", "Imports names from another file or a package; include inserts the content of a file.", "#import \"@preview/cetz:0.3.0\": canvas, draw\n#include \"chapters/intro.typ\"", "package module include file"],
        ["context", "#context expression", "Makes the contextual values (counters, state, text size, locations) available; the result depends on where it is placed.", "#context counter(page).get().first()\n#context text.size", "contextual here locate"],
        ["function call", "#name(arg1, key: value)[trailing content]", "Calls a function; positional arguments, named arguments and a trailing content block.", "#text(red)[Warning] #align(center)[Centered]", "arguments call content block"],
        ["label and reference", "<label>   @label   #ref(<label>, supplement: [Figure])", "A label after an element names it; @label references it with automatic numbering and supplement.", "= Intro <intro>\nSee @intro.", "ref cross reference label link"],
        // Text and paragraphs
        ["text", "text(font:, size:, fill:, weight:, style:, lang:, tracking:, [body])", "Sets font, size, colour, weight, language and spacing of text.", "#text(size: 14pt, weight: \"bold\", fill: red)[Hello]\n#set text(lang: \"de\", font: \"Libertinus Serif\")", "font size color colour bold language weight family"],
        ["par", "par(leading:, spacing:, justify:, first-line-indent:, linebreaks:, [body])", "Paragraph layout: line spacing, justification and first-line indent.", "#set par(justify: true, first-line-indent: 1.5em, leading: 0.8em)", "paragraph justify indent line spacing"],
        ["strong", "strong(delta:, [body])   // *body*", "Bold text.", "*bold* or #strong[bold]", "bold"],
        ["emph", "emph([body])   // _body_", "Emphasis, italic in most fonts.", "_italic_ or #emph[italic]", "italic"],
        ["underline", "underline(stroke:, offset:, evade:, [body])", "Underlines text. Also `overline` and `strike`.", "#underline[important] #strike[old]", "overline strike strikethrough line through"],
        ["highlight", "highlight(fill:, stroke:, radius:, [body])", "Marks text with a background colour.", "#highlight(fill: yellow)[note]", "mark background marker"],
        ["smallcaps", "smallcaps([body])\nupper(text)  lower(text)", "Small capitals; `upper` and `lower` change letter case.", "#smallcaps[Typst] #upper[shout]", "uppercase lowercase case caps"],
        ["sub and super", "sub([body])   super([body])", "Subscript and superscript text.", "H#sub[2]O, x#super[2]", "subscript superscript"],
        ["linebreak", "linebreak(justify: false)   // \\\nparbreak()", "A line break (backslash) or a paragraph break.", "First line \\\nSecond line", "newline break paragraph"],
        ["lorem", "lorem(words)", "Placeholder text of the given number of words.", "#lorem(40)", "placeholder dummy filler"],
        ["raw", "raw(text, block:, lang:, align:, tab-size:, theme:)   // `code` or ```lang code```", "Monospace text; with a language it is syntax highlighted.", "```python\nprint(1)\n```", "code listing verbatim monospace backtick"],
        ["quote", "quote(block:, quotes:, attribution:, [body])", "A quotation, inline or as block with attribution.", "#quote(block: true, attribution: [Knuth])[Premature optimization is the root of all evil.]", "citation blockquote"],
        ["link", "link(dest, [body])", "A hyperlink to a URL, label or location; a bare URL is a link already.", "#link(\"https://typst.app\")[Typst]", "url hyperlink"],
        ["footnote", "footnote(numbering:, [body])", "A footnote at the bottom of the page.", "Text#footnote[A remark.]", "note"],
        // Document structure
        ["page", "page(paper:, width:, height:, flipped:, margin:, columns:, fill:, numbering:, number-align:, header:, footer:, background:, foreground:, [body])", "Page size, margins, columns, numbering, header and footer. Use `set page` for the whole document.", "#set page(paper: \"a4\", margin: (x: 2cm, y: 2.5cm), numbering: \"1\")", "paper a4 margin header footer numbering size landscape flipped"],
        ["pagebreak", "pagebreak(weak: false, to: none)\ncolbreak(weak: false)", "Starts a new page (or column); `to: \"odd\"` continues on the next odd page.", "#pagebreak(weak: true)", "new page column break"],
        ["heading", "heading(level:, numbering:, supplement:, outlined:, bookmarked:, [body])   // = Title", "A section heading; the number of = signs is the level.", "#set heading(numbering: \"1.1\")\n= Introduction\n== Background", "section title numbering chapter"],
        ["outline", "outline(title:, target:, depth:, indent:, fill:)", "Table of contents; also lists of figures or tables via `target: figure.where(kind: image)`.", "#outline(depth: 2)\n#outline(title: [Figures], target: figure.where(kind: image))", "table of contents toc list of figures"],
        ["document", "document(title:, author:, keywords:, date:)", "Metadata of the document (PDF title and author).", "#set document(title: \"Thesis\", author: \"Ann\")", "metadata title author pdf"],
        ["numbering", "numbering(numbering, ..numbers)   // \"1.\" \"a)\" \"I\" \"(i)\" \"1.1\"", "Number patterns for headings, lists, pages, equations and figures.", "#set page(numbering: \"1 / 1\")\n#set enum(numbering: \"a)\")", "number pattern roman letters format"],
        ["counter", "counter(key)\n.display()  .step()  .update(n)  .get()  .at(loc)  .final()", "A counter of pages, headings, figures or your own; read it inside `context`.", "#let c = counter(\"todo\")\n#c.step() #context c.display()\n#context counter(page).display()", "page number count step"],
        ["state", "state(key, init)\n.update(value or fn)  .get()  .at(loc)  .final()", "Document-wide mutable state, read inside `context`.", "#let s = state(\"x\", 0)\n#s.update(v => v + 1) #context s.get()", "variable mutable global"],
        ["query", "query(selector)", "Finds elements of the document by selector, inside `context`.", "#context query(heading).map(h => h.body)", "selector find headings locate"],
        ["bibliography", "bibliography(path, title:, full:, style:)\ncite(key, supplement:, form:, style:)   // @key", "Bibliography from a .bib or Hayagriva file; cite with @key.", "As shown by @knuth84.\n#bibliography(\"refs.bib\", style: \"ieee\")", "references citation bibtex literature cite style"],
        ["figure", "figure(body, caption:, kind:, supplement:, numbering:, placement:, gap:, outlined:)", "A numbered, captionable element holding an image or table; referenced with a label.", "#figure(image(\"plot.png\", width: 70%), caption: [A plot]) <plot>\nSee @plot.", "caption image table numbered float placement"],
        ["image", "image(path, format:, width:, height:, alt:, fit:)", "Embeds PNG, JPEG, GIF, SVG or PDF images.", "#image(\"photo.jpg\", width: 60%)", "picture graphic png jpg svg"],
        // Layout
        ["table", "table(columns:, rows:, gutter:, column-gutter:, row-gutter:, align:, fill:, stroke:, inset:, ..children)", "A table. `columns` is a count or an array of widths (auto, 1fr, 3cm); cells follow row by row.", "#table(\n  columns: (1fr, auto),\n  align: (left, right),\n  table.header[*Item*][*Price*],\n  [Tea], [3.50],\n)", "tabular rows columns cells grid border header"],
        ["table.cell", "table.cell(x:, y:, colspan:, rowspan:, align:, fill:, stroke:, inset:, [body])\ntable.header(..cells)  table.footer(..cells)  table.hline()  table.vline()", "One cell with options: merge cells with colspan and rowspan, or style a single cell.", "#table(columns: 3,\n  table.cell(colspan: 2)[Wide], [C],\n  [A], [B], [C],\n)", "merge span colspan rowspan cell header footer hline vline"],
        ["grid", "grid(columns:, rows:, gutter:, column-gutter:, row-gutter:, align:, fill:, stroke:, inset:, ..children)", "Layout grid; like table but without semantics or default borders.", "#grid(columns: (1fr, 1fr), gutter: 1em, [Left], [Right])", "columns layout side by side"],
        ["align", "align(alignment, [body])   // left, center, right, top, horizon, bottom, start, end", "Aligns content; combine with +.", "#align(center + horizon)[Centered]", "center left right alignment"],
        ["box and block", "box(width:, height:, fill:, stroke:, inset:, outset:, radius:, baseline:, clip:, [body])\nblock(width:, height:, fill:, stroke:, inset:, radius:, breakable:, above:, below:, spacing:, [body])", "An inline box or a block-level container with background, border and padding.", "#block(fill: luma(240), inset: 8pt, radius: 4pt)[A note]", "container frame background border padding radius inline"],
        ["pad", "pad(left:, right:, top:, bottom:, x:, y:, rest:, [body])", "Adds space around content.", "#pad(x: 1cm)[Indented]", "padding margin space around inset"],
        ["stack", "stack(dir:, spacing:, ..children)", "Places children in a row or column.", "#stack(dir: ltr, spacing: 1em, [A], [B])", "row column horizontal vertical"],
        ["h and v", "h(amount, weak: false)\nv(amount, weak: false)", "Horizontal or vertical space; `1fr` fills the remaining space.", "Left #h(1fr) Right\n#v(1em)", "space gap spacing fill fr"],
        ["place", "place(alignment, scope:, float:, clearance:, dx:, dy:, [body])", "Positions content without taking space; `float: true` lets it float to the top or bottom of the page.", "#place(top + right, dx: -1cm)[Draft]", "position absolute float overlay"],
        ["columns", "columns(count, gutter:, [body])", "Flows content into columns; for a whole page use `set page(columns: 2)`.", "#columns(2)[#lorem(60)]", "column multi newspaper"],
        ["rotate and scale", "rotate(angle, origin:, reflow:, [body])\nscale(factor, x:, y:, origin:, reflow:, [body])\nmove(dx:, dy:, [body])", "Transform content without changing the layout unless `reflow: true`.", "#rotate(90deg)[Sideways] #scale(80%)[Small]", "transform angle zoom shift"],
        ["repeat", "repeat(gap:, justify:, [body])", "Repeats content to fill the line, e.g. dot leaders.", "Chapter #box(width: 1fr, repeat[.]) 12", "dots leader fill"],
        ["rect and shapes", "rect(width:, height:, fill:, stroke:, radius:, inset:, [body])\ncircle(radius:, ...)  ellipse(...)  square(size:, ...)\nline(start:, end:, length:, angle:, stroke:)\npolygon(..vertices)", "Basic shapes; some can hold content.", "#rect(fill: blue.lighten(80%), inset: 6pt)[Text]\n#line(length: 100%)", "rectangle circle line polygon draw shape stroke"],
        ["list, enum, terms", "list(tight:, marker:, indent:, body-indent:, ..children)   // - item\nenum(numbering:, start:, tight:, ..children)   // + item\nterms(separator:, ..children)   // / Term: text", "Bullet, numbered and term lists.", "#set enum(numbering: \"a)\")\n+ First\n+ Second\n/ Typst: A typesetting system", "bullet numbered list items description"],
        ["layout and measure", "layout(size => content)\nmeasure(content)   // inside context", "Reads the available size or the size of content to compute a layout.", "#layout(size => [Width: #size.width])\n#context measure[Text].width", "size width height responsive"],
        // Colours, units, data
        ["color", "rgb(\"#3366cc\")  rgb(r, g, b, a)  luma(l)  cmyk(c, m, y, k)\ncolor.mix(..)  c.lighten(%)  c.darken(%)  c.transparentize(%)\ngradient.linear(..stops, angle:)", "Colour values and gradients. Named colours: red, blue, green, black, white, gray, navy, teal, ...", "#text(fill: rgb(\"#ff6600\").darken(10%))[Orange]\n#rect(fill: gradient.linear(red, blue))", "colour rgb hex fill gradient lighten darken"],
        ["length", "1pt  2mm  1.5cm  1in  1em  50%  1fr  90deg", "Units: pt, mm, cm, in, em (font size), % of the container, fr (fraction of leftover space), deg and rad for angles.", "#rect(width: 50%, height: 2cm)", "unit size em pt mm cm percent fraction"],
        ["stroke", "stroke(paint:, thickness:, dash:, cap:, join:)   // 1pt + red", "Line style; usually written as thickness plus colour.", "#rect(stroke: (bottom: 1pt + gray))", "border line dash outline"],
        ["array", "(1, 2, 3)  .len() .at(i) .first() .last() .push(x) .map(f) .filter(f) .fold(init, f) .join(sep) .enumerate() .zip(other) .sorted(key:) .contains(x) .slice(a, b)  range(n)", "Ordered list of values with many methods.", "#let xs = (1, 2, 3)\n#xs.map(x => x * 2).join(\", \")\n#range(5).sum()", "list map filter sort join method"],
        ["dictionary", "(key: value)  .at(\"key\") .keys() .values() .pairs() .insert(k, v) .remove(k)", "Key-value map; iterate with `for (k, v) in dict`.", "#let d = (name: \"Ann\", age: 3)\n#d.name, #d.at(\"age\")", "map object keys"],
        ["str", "str.len()  .split(sep)  .replace(a, b)  .contains(x)  .starts-with(x)  .trim()  .slice(a, b)  .at(i)", "Strings and their methods; `str(5)` converts, `int(\"5\")` parses.", "#\"a,b\".split(\",\")\n#\"hello\".replace(\"l\", \"L\")", "string text method replace split regex"],
        ["calc", "calc.pow(a, b) calc.sqrt(x) calc.abs(x) calc.round(x, digits: n) calc.floor(x) calc.ceil(x) calc.min(..) calc.max(..) calc.rem(a, b) calc.quo(a, b) calc.sin(x) calc.log(x) calc.pi", "Maths functions for scripting.", "#calc.round(3.14159, digits: 2)\n#calc.max(1, 5, 3)", "math arithmetic round modulo power"],
        ["datetime", "datetime(year:, month:, day:)  datetime.today()  .display(format)", "Dates and times; `display` takes a format like \"[day].[month].[year]\".", "#datetime.today().display(\"[day].[month].[year]\")", "date today time format"],
        ["read and data", "read(path)  json(path)  csv(path)  yaml(path)  toml(path)  xml(path)", "Loads files of the project as text or data.", "#let rows = csv(\"data.csv\")\n#for r in rows.slice(1) [#r.join(\" · \") \\ ]", "file load data csv json import"],
        ["metadata", "metadata(value)   sys.inputs", "Hidden data for `query`; `sys.inputs` holds values passed on the command line.", "#metadata(\"v1\") <version>", "hidden data inputs"],
        ["type conversion", "int(x) float(x) str(x) repr(x) type(x) array(x) bool", "Converts between types; `repr` shows a value as code.", "#int(\"12\") + 1\n#repr((1, 2))", "convert cast to string number type"],
        ["assert and panic", "assert(condition, message:)  panic(..)  eval(code, mode:)", "Checks in scripts; `eval` runs a string as Typst code.", "#assert(x > 0, message: \"positive\")", "error check debug"],
        // Maths
        ["math", "$ x^2 + y_1 $   // spaces inside the dollars make it a block\n$a/b$  $sqrt(x)$  $sum_(i=1)^n i$  $integral_0^1 f(x) dif x$", "Maths in dollar signs: ^ and _ for scripts, / for fractions, functions without #, multi-letter names are functions, quote text with \"\".", "$ sum_(k=1)^n k = (n(n+1))/2 $", "equation formula dollar sum integral fraction script"],
        ["math.equation", "math.equation(block:, numbering:, supplement:, [body])", "An equation element; number equations with `set math.equation(numbering: \"(1)\")` and label them to reference.", "#set math.equation(numbering: \"(1)\")\n$ E = m c^2 $ <emc>\nSee @emc.", "equation numbering number label block inline"],
        ["math.frac and roots", "frac(num, denom)   a/b\nsqrt(x)   root(n, x)\nbinom(n, k)", "Fractions, roots and binomials.", "$ frac(a + b, 2) quad sqrt(x) quad root(3, x) $", "fraction division square root"],
        ["math.vec and mat", "vec(delim:, ..elements)\nmat(delim:, ..rows)   // rows separated by ;\ncases(..branches)", "Vectors, matrices and case distinctions.", "$ mat(1, 2; 3, 4) quad vec(x, y) $\n$ f(x) = cases(1 &\"if\" x > 0, 0 &\"else\") $", "matrix vector cases brackets piecewise"],
        ["math.lr", "lr(body)  abs(x)  norm(x)  floor(x)  ceil(x)  round(x)", "Delimiters that scale with their content, and abs, norm, floor, ceil.", "$ lr(( a / b )) quad abs(x) quad norm(v) $", "brackets parentheses delimiter size"],
        ["math fonts and accents", "bold(x) italic(x) upright(x) cal(x) bb(x) frak(x) mono(x) sans(x)\narrow(x) hat(x) tilde(x) bar(x) dot(x) overline(x) underbrace(x, t) cancel(x)", "Math alphabets and accents.", "$ bb(R) quad cal(L) quad hat(x) quad arrow(v) quad overbrace(a + b, \"sum\") $", "blackboard calligraphic vector hat bar font"],
        ["math.op", "op(\"name\", limits: false)   lim  max  sin  log  dif", "Operators; `lim` and `max` put their limits below, define your own with `op`.", "$ lim_(x -> oo) 1/x = 0 quad op(\"rank\")(A) $", "limit operator function name"],
        ["math alignment", "$ a &= b + c \\\n  &= d $", "Align lines of a block equation at & and break lines with a backslash.", "$ x &= 1 + 2 \\\n  &= 3 $", "align multiline equations ampersand"],
        ["symbols", "sym.arrow.r  sym.alpha  emoji.face  $arrow.r$  #sym.dots", "Symbols by name with modifiers after dots; `emoji.` holds emoji.", "$alpha + beta -> gamma$ #sym.arrow.r", "greek arrow dots emoji character unicode"],
    ]
}
