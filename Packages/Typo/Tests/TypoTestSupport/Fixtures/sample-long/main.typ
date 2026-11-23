#import "@preview/showybox:2.0.4": showybox
#set page(paper: "a4", margin: 2.2cm, numbering: "1")
#set text(size: 11pt)
#set heading(numbering: "1.1")
#set par(justify: true)

#align(center)[#text(22pt, weight: "bold")[A Long Sample Document] \ #v(4pt) Spike benchmark input]
#outline()
#pagebreak()

= Chapter 1: Topic number 1 <ch1>

== Section 1.1

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch1, the details of case 1.1.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch1, the details of case 1.1.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch1, the details of case 1.1.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch1, the details of case 1.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 1.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 1a], [1.1], [2.1], [3.1], [row 1b], [4.1], [5.1], [6.1], [row 1c], [7.1], [8.1], [9.1]), caption: [Measurements for chapter 1.]) <tab1>

== Section 1.2

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch1, the details of case 1.2.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch1, the details of case 1.2.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch1, the details of case 1.2.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch1, the details of case 1.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 1.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 1]], caption: [A figure in chapter 1, referenced from @tab1.]) <fig1>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 1.3

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch1, the details of case 1.3.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch1, the details of case 1.3.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch1, the details of case 1.3.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch1, the details of case 1.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 1.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig1

= Chapter 2: Topic number 2 <ch2>

== Section 2.1

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch1, the details of case 2.1.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch1, the details of case 2.1.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch1, the details of case 2.1.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch1, the details of case 2.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 2.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 2a], [1.2], [2.2], [3.2], [row 2b], [4.2], [5.2], [6.2], [row 2c], [7.2], [8.2], [9.2]), caption: [Measurements for chapter 2.]) <tab2>

== Section 2.2

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch1, the details of case 2.2.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch1, the details of case 2.2.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch1, the details of case 2.2.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch1, the details of case 2.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 2.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 2]], caption: [A figure in chapter 2, referenced from @tab2.]) <fig2>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 2.3

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch1, the details of case 2.3.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch1, the details of case 2.3.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch1, the details of case 2.3.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch1, the details of case 2.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 2.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig2

= Chapter 3: Topic number 3 <ch3>

== Section 3.1

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch2, the details of case 3.1.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch2, the details of case 3.1.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch2, the details of case 3.1.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch2, the details of case 3.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 3.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 3a], [1.3], [2.3], [3.3], [row 3b], [4.3], [5.3], [6.3], [row 3c], [7.3], [8.3], [9.3]), caption: [Measurements for chapter 3.]) <tab3>

== Section 3.2

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch2, the details of case 3.2.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch2, the details of case 3.2.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch2, the details of case 3.2.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch2, the details of case 3.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 3.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 3]], caption: [A figure in chapter 3, referenced from @tab3.]) <fig3>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 3.3

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch2, the details of case 3.3.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch2, the details of case 3.3.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch2, the details of case 3.3.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch2, the details of case 3.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 3.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig3

= Chapter 4: Topic number 4 <ch4>

== Section 4.1

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch3, the details of case 4.1.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch3, the details of case 4.1.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch3, the details of case 4.1.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch3, the details of case 4.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 4.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 4a], [1.4], [2.4], [3.4], [row 4b], [4.4], [5.4], [6.4], [row 4c], [7.4], [8.4], [9.4]), caption: [Measurements for chapter 4.]) <tab4>

== Section 4.2

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch3, the details of case 4.2.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch3, the details of case 4.2.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch3, the details of case 4.2.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch3, the details of case 4.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 4.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 4]], caption: [A figure in chapter 4, referenced from @tab4.]) <fig4>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 4.3

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch3, the details of case 4.3.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch3, the details of case 4.3.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch3, the details of case 4.3.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch3, the details of case 4.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 4.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig4

= Chapter 5: Topic number 5 <ch5>

== Section 5.1

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch4, the details of case 5.1.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch4, the details of case 5.1.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch4, the details of case 5.1.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch4, the details of case 5.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 5.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 5a], [1.5], [2.5], [3.5], [row 5b], [4.5], [5.5], [6.5], [row 5c], [7.5], [8.5], [9.5]), caption: [Measurements for chapter 5.]) <tab5>

== Section 5.2

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch4, the details of case 5.2.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch4, the details of case 5.2.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch4, the details of case 5.2.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch4, the details of case 5.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 5.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 5]], caption: [A figure in chapter 5, referenced from @tab5.]) <fig5>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 5.3

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch4, the details of case 5.3.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch4, the details of case 5.3.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch4, the details of case 5.3.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch4, the details of case 5.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 5.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig5

= Chapter 6: Topic number 6 <ch6>

== Section 6.1

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch5, the details of case 6.1.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch5, the details of case 6.1.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch5, the details of case 6.1.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch5, the details of case 6.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 6.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 6a], [1.6], [2.6], [3.6], [row 6b], [4.6], [5.6], [6.6], [row 6c], [7.6], [8.6], [9.6]), caption: [Measurements for chapter 6.]) <tab6>

== Section 6.2

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch5, the details of case 6.2.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch5, the details of case 6.2.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch5, the details of case 6.2.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch5, the details of case 6.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 6.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 6]], caption: [A figure in chapter 6, referenced from @tab6.]) <fig6>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 6.3

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch5, the details of case 6.3.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch5, the details of case 6.3.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch5, the details of case 6.3.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch5, the details of case 6.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 6.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig6

= Chapter 7: Topic number 7 <ch7>

== Section 7.1

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch6, the details of case 7.1.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch6, the details of case 7.1.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch6, the details of case 7.1.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch6, the details of case 7.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 7.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 7a], [1.7], [2.7], [3.7], [row 7b], [4.7], [5.7], [6.7], [row 7c], [7.7], [8.7], [9.7]), caption: [Measurements for chapter 7.]) <tab7>

== Section 7.2

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch6, the details of case 7.2.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch6, the details of case 7.2.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch6, the details of case 7.2.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch6, the details of case 7.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 7.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 7]], caption: [A figure in chapter 7, referenced from @tab7.]) <fig7>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 7.3

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch6, the details of case 7.3.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch6, the details of case 7.3.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch6, the details of case 7.3.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch6, the details of case 7.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 7.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig7

= Chapter 8: Topic number 8 <ch8>

== Section 8.1

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch7, the details of case 8.1.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch7, the details of case 8.1.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch7, the details of case 8.1.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch7, the details of case 8.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 8.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 8a], [1.8], [2.8], [3.8], [row 8b], [4.8], [5.8], [6.8], [row 8c], [7.8], [8.8], [9.8]), caption: [Measurements for chapter 8.]) <tab8>

== Section 8.2

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch7, the details of case 8.2.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch7, the details of case 8.2.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch7, the details of case 8.2.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch7, the details of case 8.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 8.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 8]], caption: [A figure in chapter 8, referenced from @tab8.]) <fig8>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 8.3

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch7, the details of case 8.3.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch7, the details of case 8.3.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch7, the details of case 8.3.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch7, the details of case 8.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 8.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig8

= Chapter 9: Topic number 9 <ch9>

== Section 9.1

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch8, the details of case 9.1.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch8, the details of case 9.1.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch8, the details of case 9.1.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch8, the details of case 9.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 9.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 9a], [1.9], [2.9], [3.9], [row 9b], [4.9], [5.9], [6.9], [row 9c], [7.9], [8.9], [9.9]), caption: [Measurements for chapter 9.]) <tab9>

== Section 9.2

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch8, the details of case 9.2.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch8, the details of case 9.2.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch8, the details of case 9.2.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch8, the details of case 9.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 9.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 9]], caption: [A figure in chapter 9, referenced from @tab9.]) <fig9>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 9.3

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch8, the details of case 9.3.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch8, the details of case 9.3.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch8, the details of case 9.3.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch8, the details of case 9.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 9.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig9

= Chapter 10: Topic number 10 <ch10>

== Section 10.1

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch9, the details of case 10.1.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch9, the details of case 10.1.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch9, the details of case 10.1.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch9, the details of case 10.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 10.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 10a], [1.10], [2.10], [3.10], [row 10b], [4.10], [5.10], [6.10], [row 10c], [7.10], [8.10], [9.10]), caption: [Measurements for chapter 10.]) <tab10>

== Section 10.2

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch9, the details of case 10.2.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch9, the details of case 10.2.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch9, the details of case 10.2.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch9, the details of case 10.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 10.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 10]], caption: [A figure in chapter 10, referenced from @tab10.]) <fig10>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 10.3

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch9, the details of case 10.3.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch9, the details of case 10.3.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch9, the details of case 10.3.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch9, the details of case 10.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 10.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig10

= Chapter 11: Topic number 11 <ch11>

== Section 11.1

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch10, the details of case 11.1.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch10, the details of case 11.1.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch10, the details of case 11.1.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch10, the details of case 11.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 11.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 11a], [1.11], [2.11], [3.11], [row 11b], [4.11], [5.11], [6.11], [row 11c], [7.11], [8.11], [9.11]), caption: [Measurements for chapter 11.]) <tab11>

== Section 11.2

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch10, the details of case 11.2.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch10, the details of case 11.2.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch10, the details of case 11.2.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch10, the details of case 11.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 11.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 11]], caption: [A figure in chapter 11, referenced from @tab11.]) <fig11>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 11.3

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch10, the details of case 11.3.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch10, the details of case 11.3.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch10, the details of case 11.3.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch10, the details of case 11.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 11.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig11

= Chapter 12: Topic number 12 <ch12>

== Section 12.1

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch11, the details of case 12.1.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch11, the details of case 12.1.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch11, the details of case 12.1.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch11, the details of case 12.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 12.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 12a], [1.12], [2.12], [3.12], [row 12b], [4.12], [5.12], [6.12], [row 12c], [7.12], [8.12], [9.12]), caption: [Measurements for chapter 12.]) <tab12>

== Section 12.2

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch11, the details of case 12.2.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch11, the details of case 12.2.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch11, the details of case 12.2.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch11, the details of case 12.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 12.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 12]], caption: [A figure in chapter 12, referenced from @tab12.]) <fig12>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 12.3

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch11, the details of case 12.3.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch11, the details of case 12.3.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch11, the details of case 12.3.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch11, the details of case 12.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 12.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig12

= Chapter 13: Topic number 13 <ch13>

== Section 13.1

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch12, the details of case 13.1.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch12, the details of case 13.1.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch12, the details of case 13.1.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch12, the details of case 13.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 13.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 13a], [1.13], [2.13], [3.13], [row 13b], [4.13], [5.13], [6.13], [row 13c], [7.13], [8.13], [9.13]), caption: [Measurements for chapter 13.]) <tab13>

== Section 13.2

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch12, the details of case 13.2.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch12, the details of case 13.2.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch12, the details of case 13.2.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch12, the details of case 13.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 13.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 13]], caption: [A figure in chapter 13, referenced from @tab13.]) <fig13>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 13.3

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch12, the details of case 13.3.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch12, the details of case 13.3.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch12, the details of case 13.3.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch12, the details of case 13.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 13.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig13

= Chapter 14: Topic number 14 <ch14>

== Section 14.1

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch13, the details of case 14.1.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch13, the details of case 14.1.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch13, the details of case 14.1.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch13, the details of case 14.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 14.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 14a], [1.14], [2.14], [3.14], [row 14b], [4.14], [5.14], [6.14], [row 14c], [7.14], [8.14], [9.14]), caption: [Measurements for chapter 14.]) <tab14>

== Section 14.2

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch13, the details of case 14.2.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch13, the details of case 14.2.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch13, the details of case 14.2.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch13, the details of case 14.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 14.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 14]], caption: [A figure in chapter 14, referenced from @tab14.]) <fig14>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 14.3

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch13, the details of case 14.3.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch13, the details of case 14.3.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch13, the details of case 14.3.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch13, the details of case 14.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 14.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig14

= Chapter 15: Topic number 15 <ch15>

== Section 15.1

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch14, the details of case 15.1.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch14, the details of case 15.1.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch14, the details of case 15.1.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch14, the details of case 15.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 15.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 15a], [1.15], [2.15], [3.15], [row 15b], [4.15], [5.15], [6.15], [row 15c], [7.15], [8.15], [9.15]), caption: [Measurements for chapter 15.]) <tab15>

== Section 15.2

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch14, the details of case 15.2.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch14, the details of case 15.2.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch14, the details of case 15.2.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch14, the details of case 15.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 15.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 15]], caption: [A figure in chapter 15, referenced from @tab15.]) <fig15>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 15.3

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch14, the details of case 15.3.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch14, the details of case 15.3.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch14, the details of case 15.3.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch14, the details of case 15.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 15.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig15

= Chapter 16: Topic number 16 <ch16>

== Section 16.1

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch15, the details of case 16.1.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch15, the details of case 16.1.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch15, the details of case 16.1.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch15, the details of case 16.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 16.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 16a], [1.16], [2.16], [3.16], [row 16b], [4.16], [5.16], [6.16], [row 16c], [7.16], [8.16], [9.16]), caption: [Measurements for chapter 16.]) <tab16>

== Section 16.2

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch15, the details of case 16.2.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch15, the details of case 16.2.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch15, the details of case 16.2.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch15, the details of case 16.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 16.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 16]], caption: [A figure in chapter 16, referenced from @tab16.]) <fig16>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 16.3

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch15, the details of case 16.3.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch15, the details of case 16.3.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch15, the details of case 16.3.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch15, the details of case 16.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 16.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig16

= Chapter 17: Topic number 17 <ch17>

== Section 17.1

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch16, the details of case 17.1.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch16, the details of case 17.1.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch16, the details of case 17.1.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch16, the details of case 17.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 17.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 17a], [1.17], [2.17], [3.17], [row 17b], [4.17], [5.17], [6.17], [row 17c], [7.17], [8.17], [9.17]), caption: [Measurements for chapter 17.]) <tab17>

== Section 17.2

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch16, the details of case 17.2.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch16, the details of case 17.2.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch16, the details of case 17.2.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch16, the details of case 17.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 17.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 17]], caption: [A figure in chapter 17, referenced from @tab17.]) <fig17>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 17.3

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch16, the details of case 17.3.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch16, the details of case 17.3.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch16, the details of case 17.3.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch16, the details of case 17.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 17.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig17

= Chapter 18: Topic number 18 <ch18>

== Section 18.1

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch17, the details of case 18.1.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch17, the details of case 18.1.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch17, the details of case 18.1.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch17, the details of case 18.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 18.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 18a], [1.18], [2.18], [3.18], [row 18b], [4.18], [5.18], [6.18], [row 18c], [7.18], [8.18], [9.18]), caption: [Measurements for chapter 18.]) <tab18>

== Section 18.2

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch17, the details of case 18.2.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch17, the details of case 18.2.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch17, the details of case 18.2.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch17, the details of case 18.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 18.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 18]], caption: [A figure in chapter 18, referenced from @tab18.]) <fig18>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 18.3

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch17, the details of case 18.3.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch17, the details of case 18.3.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch17, the details of case 18.3.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch17, the details of case 18.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 18.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig18

= Chapter 19: Topic number 19 <ch19>

== Section 19.1

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch18, the details of case 19.1.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch18, the details of case 19.1.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch18, the details of case 19.1.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch18, the details of case 19.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 19.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 19a], [1.19], [2.19], [3.19], [row 19b], [4.19], [5.19], [6.19], [row 19c], [7.19], [8.19], [9.19]), caption: [Measurements for chapter 19.]) <tab19>

== Section 19.2

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch18, the details of case 19.2.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch18, the details of case 19.2.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch18, the details of case 19.2.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch18, the details of case 19.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 19.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 19]], caption: [A figure in chapter 19, referenced from @tab19.]) <fig19>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 19.3

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch18, the details of case 19.3.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch18, the details of case 19.3.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch18, the details of case 19.3.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch18, the details of case 19.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 19.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig19

= Chapter 20: Topic number 20 <ch20>

== Section 20.1

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch19, the details of case 20.1.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch19, the details of case 20.1.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch19, the details of case 20.1.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch19, the details of case 20.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 20.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 20a], [1.20], [2.20], [3.20], [row 20b], [4.20], [5.20], [6.20], [row 20c], [7.20], [8.20], [9.20]), caption: [Measurements for chapter 20.]) <tab20>

== Section 20.2

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch19, the details of case 20.2.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch19, the details of case 20.2.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch19, the details of case 20.2.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch19, the details of case 20.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 20.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 20]], caption: [A figure in chapter 20, referenced from @tab20.]) <fig20>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 20.3

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch19, the details of case 20.3.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch19, the details of case 20.3.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch19, the details of case 20.3.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch19, the details of case 20.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 20.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig20

= Chapter 21: Topic number 21 <ch21>

== Section 21.1

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch20, the details of case 21.1.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch20, the details of case 21.1.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch20, the details of case 21.1.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch20, the details of case 21.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 21.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 21a], [1.21], [2.21], [3.21], [row 21b], [4.21], [5.21], [6.21], [row 21c], [7.21], [8.21], [9.21]), caption: [Measurements for chapter 21.]) <tab21>

== Section 21.2

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch20, the details of case 21.2.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch20, the details of case 21.2.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch20, the details of case 21.2.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch20, the details of case 21.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 21.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 21]], caption: [A figure in chapter 21, referenced from @tab21.]) <fig21>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 21.3

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch20, the details of case 21.3.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch20, the details of case 21.3.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch20, the details of case 21.3.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch20, the details of case 21.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 21.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig21

= Chapter 22: Topic number 22 <ch22>

== Section 22.1

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch21, the details of case 22.1.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch21, the details of case 22.1.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch21, the details of case 22.1.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch21, the details of case 22.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 22.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 22a], [1.22], [2.22], [3.22], [row 22b], [4.22], [5.22], [6.22], [row 22c], [7.22], [8.22], [9.22]), caption: [Measurements for chapter 22.]) <tab22>

== Section 22.2

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch21, the details of case 22.2.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch21, the details of case 22.2.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch21, the details of case 22.2.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch21, the details of case 22.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 22.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 22]], caption: [A figure in chapter 22, referenced from @tab22.]) <fig22>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 22.3

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch21, the details of case 22.3.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch21, the details of case 22.3.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch21, the details of case 22.3.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch21, the details of case 22.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 22.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig22

= Chapter 23: Topic number 23 <ch23>

== Section 23.1

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch22, the details of case 23.1.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch22, the details of case 23.1.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch22, the details of case 23.1.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch22, the details of case 23.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 23.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 23a], [1.23], [2.23], [3.23], [row 23b], [4.23], [5.23], [6.23], [row 23c], [7.23], [8.23], [9.23]), caption: [Measurements for chapter 23.]) <tab23>

== Section 23.2

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch22, the details of case 23.2.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch22, the details of case 23.2.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch22, the details of case 23.2.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch22, the details of case 23.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 23.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 23]], caption: [A figure in chapter 23, referenced from @tab23.]) <fig23>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 23.3

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch22, the details of case 23.3.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch22, the details of case 23.3.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch22, the details of case 23.3.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch22, the details of case 23.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 23.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig23

= Chapter 24: Topic number 24 <ch24>

== Section 24.1

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch23, the details of case 24.1.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch23, the details of case 24.1.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch23, the details of case 24.1.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch23, the details of case 24.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 24.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 24a], [1.24], [2.24], [3.24], [row 24b], [4.24], [5.24], [6.24], [row 24c], [7.24], [8.24], [9.24]), caption: [Measurements for chapter 24.]) <tab24>

== Section 24.2

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch23, the details of case 24.2.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch23, the details of case 24.2.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch23, the details of case 24.2.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch23, the details of case 24.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 24.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 24]], caption: [A figure in chapter 24, referenced from @tab24.]) <fig24>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 24.3

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch23, the details of case 24.3.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch23, the details of case 24.3.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch23, the details of case 24.3.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch23, the details of case 24.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 24.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig24

= Chapter 25: Topic number 25 <ch25>

== Section 25.1

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch24, the details of case 25.1.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch24, the details of case 25.1.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch24, the details of case 25.1.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch24, the details of case 25.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 25.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 25a], [1.25], [2.25], [3.25], [row 25b], [4.25], [5.25], [6.25], [row 25c], [7.25], [8.25], [9.25]), caption: [Measurements for chapter 25.]) <tab25>

== Section 25.2

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch24, the details of case 25.2.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch24, the details of case 25.2.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch24, the details of case 25.2.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch24, the details of case 25.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 25.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 25]], caption: [A figure in chapter 25, referenced from @tab25.]) <fig25>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 25.3

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch24, the details of case 25.3.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch24, the details of case 25.3.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch24, the details of case 25.3.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch24, the details of case 25.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 25.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig25

= Chapter 26: Topic number 26 <ch26>

== Section 26.1

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch25, the details of case 26.1.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch25, the details of case 26.1.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch25, the details of case 26.1.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch25, the details of case 26.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 26.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 26a], [1.26], [2.26], [3.26], [row 26b], [4.26], [5.26], [6.26], [row 26c], [7.26], [8.26], [9.26]), caption: [Measurements for chapter 26.]) <tab26>

== Section 26.2

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch25, the details of case 26.2.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch25, the details of case 26.2.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch25, the details of case 26.2.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch25, the details of case 26.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 26.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 26]], caption: [A figure in chapter 26, referenced from @tab26.]) <fig26>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 26.3

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch25, the details of case 26.3.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch25, the details of case 26.3.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch25, the details of case 26.3.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch25, the details of case 26.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 26.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig26

= Chapter 27: Topic number 27 <ch27>

== Section 27.1

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch26, the details of case 27.1.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch26, the details of case 27.1.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch26, the details of case 27.1.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch26, the details of case 27.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 27.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 27a], [1.27], [2.27], [3.27], [row 27b], [4.27], [5.27], [6.27], [row 27c], [7.27], [8.27], [9.27]), caption: [Measurements for chapter 27.]) <tab27>

== Section 27.2

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch26, the details of case 27.2.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch26, the details of case 27.2.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch26, the details of case 27.2.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch26, the details of case 27.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 27.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 27]], caption: [A figure in chapter 27, referenced from @tab27.]) <fig27>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 27.3

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch26, the details of case 27.3.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch26, the details of case 27.3.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch26, the details of case 27.3.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch26, the details of case 27.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 27.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig27

= Chapter 28: Topic number 28 <ch28>

== Section 28.1

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch27, the details of case 28.1.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch27, the details of case 28.1.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch27, the details of case 28.1.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch27, the details of case 28.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 28.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 28a], [1.28], [2.28], [3.28], [row 28b], [4.28], [5.28], [6.28], [row 28c], [7.28], [8.28], [9.28]), caption: [Measurements for chapter 28.]) <tab28>

== Section 28.2

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch27, the details of case 28.2.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch27, the details of case 28.2.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch27, the details of case 28.2.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch27, the details of case 28.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 28.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 28]], caption: [A figure in chapter 28, referenced from @tab28.]) <fig28>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 28.3

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch27, the details of case 28.3.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch27, the details of case 28.3.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch27, the details of case 28.3.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch27, the details of case 28.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 28.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig28

= Chapter 29: Topic number 29 <ch29>

== Section 29.1

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch28, the details of case 29.1.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch28, the details of case 29.1.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch28, the details of case 29.1.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch28, the details of case 29.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 29.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 29a], [1.29], [2.29], [3.29], [row 29b], [4.29], [5.29], [6.29], [row 29c], [7.29], [8.29], [9.29]), caption: [Measurements for chapter 29.]) <tab29>

== Section 29.2

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch28, the details of case 29.2.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch28, the details of case 29.2.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch28, the details of case 29.2.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch28, the details of case 29.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 29.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 29]], caption: [A figure in chapter 29, referenced from @tab29.]) <fig29>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 29.3

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch28, the details of case 29.3.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch28, the details of case 29.3.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch28, the details of case 29.3.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch28, the details of case 29.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 29.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig29

= Chapter 30: Topic number 30 <ch30>

== Section 30.1

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch29, the details of case 30.1.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch29, the details of case 30.1.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch29, the details of case 30.1.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch29, the details of case 30.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 30.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 30a], [1.30], [2.30], [3.30], [row 30b], [4.30], [5.30], [6.30], [row 30c], [7.30], [8.30], [9.30]), caption: [Measurements for chapter 30.]) <tab30>

== Section 30.2

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch29, the details of case 30.2.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch29, the details of case 30.2.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch29, the details of case 30.2.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch29, the details of case 30.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 30.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 30]], caption: [A figure in chapter 30, referenced from @tab30.]) <fig30>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 30.3

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch29, the details of case 30.3.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch29, the details of case 30.3.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch29, the details of case 30.3.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch29, the details of case 30.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 30.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig30

= Chapter 31: Topic number 31 <ch31>

== Section 31.1

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch30, the details of case 31.1.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch30, the details of case 31.1.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch30, the details of case 31.1.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch30, the details of case 31.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 31.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 31a], [1.31], [2.31], [3.31], [row 31b], [4.31], [5.31], [6.31], [row 31c], [7.31], [8.31], [9.31]), caption: [Measurements for chapter 31.]) <tab31>

== Section 31.2

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch30, the details of case 31.2.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch30, the details of case 31.2.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch30, the details of case 31.2.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch30, the details of case 31.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 31.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 31]], caption: [A figure in chapter 31, referenced from @tab31.]) <fig31>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 31.3

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch30, the details of case 31.3.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch30, the details of case 31.3.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch30, the details of case 31.3.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch30, the details of case 31.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 31.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig31

= Chapter 32: Topic number 32 <ch32>

== Section 32.1

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch31, the details of case 32.1.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch31, the details of case 32.1.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch31, the details of case 32.1.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch31, the details of case 32.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 32.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 32a], [1.32], [2.32], [3.32], [row 32b], [4.32], [5.32], [6.32], [row 32c], [7.32], [8.32], [9.32]), caption: [Measurements for chapter 32.]) <tab32>

== Section 32.2

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch31, the details of case 32.2.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch31, the details of case 32.2.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch31, the details of case 32.2.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch31, the details of case 32.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 32.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 32]], caption: [A figure in chapter 32, referenced from @tab32.]) <fig32>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 32.3

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch31, the details of case 32.3.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch31, the details of case 32.3.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch31, the details of case 32.3.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch31, the details of case 32.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 32.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig32

= Chapter 33: Topic number 33 <ch33>

== Section 33.1

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch32, the details of case 33.1.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch32, the details of case 33.1.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch32, the details of case 33.1.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch32, the details of case 33.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 33.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 33a], [1.33], [2.33], [3.33], [row 33b], [4.33], [5.33], [6.33], [row 33c], [7.33], [8.33], [9.33]), caption: [Measurements for chapter 33.]) <tab33>

== Section 33.2

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch32, the details of case 33.2.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch32, the details of case 33.2.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch32, the details of case 33.2.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch32, the details of case 33.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 33.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 33]], caption: [A figure in chapter 33, referenced from @tab33.]) <fig33>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 33.3

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch32, the details of case 33.3.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch32, the details of case 33.3.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch32, the details of case 33.3.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch32, the details of case 33.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 33.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig33

= Chapter 34: Topic number 34 <ch34>

== Section 34.1

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch33, the details of case 34.1.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch33, the details of case 34.1.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch33, the details of case 34.1.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch33, the details of case 34.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 34.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 34a], [1.34], [2.34], [3.34], [row 34b], [4.34], [5.34], [6.34], [row 34c], [7.34], [8.34], [9.34]), caption: [Measurements for chapter 34.]) <tab34>

== Section 34.2

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch33, the details of case 34.2.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch33, the details of case 34.2.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch33, the details of case 34.2.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch33, the details of case 34.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 34.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 34]], caption: [A figure in chapter 34, referenced from @tab34.]) <fig34>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 34.3

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch33, the details of case 34.3.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch33, the details of case 34.3.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch33, the details of case 34.3.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch33, the details of case 34.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 34.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig34

= Chapter 35: Topic number 35 <ch35>

== Section 35.1

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch34, the details of case 35.1.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch34, the details of case 35.1.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch34, the details of case 35.1.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch34, the details of case 35.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 35.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 35a], [1.35], [2.35], [3.35], [row 35b], [4.35], [5.35], [6.35], [row 35c], [7.35], [8.35], [9.35]), caption: [Measurements for chapter 35.]) <tab35>

== Section 35.2

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch34, the details of case 35.2.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch34, the details of case 35.2.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch34, the details of case 35.2.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch34, the details of case 35.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 35.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 35]], caption: [A figure in chapter 35, referenced from @tab35.]) <fig35>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 35.3

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch34, the details of case 35.3.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch34, the details of case 35.3.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch34, the details of case 35.3.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch34, the details of case 35.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 35.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig35

= Chapter 36: Topic number 36 <ch36>

== Section 36.1

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch35, the details of case 36.1.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch35, the details of case 36.1.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch35, the details of case 36.1.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch35, the details of case 36.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 36.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 36a], [1.36], [2.36], [3.36], [row 36b], [4.36], [5.36], [6.36], [row 36c], [7.36], [8.36], [9.36]), caption: [Measurements for chapter 36.]) <tab36>

== Section 36.2

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch35, the details of case 36.2.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch35, the details of case 36.2.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch35, the details of case 36.2.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch35, the details of case 36.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 36.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 36]], caption: [A figure in chapter 36, referenced from @tab36.]) <fig36>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 36.3

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch35, the details of case 36.3.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch35, the details of case 36.3.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch35, the details of case 36.3.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch35, the details of case 36.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 36.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig36

= Chapter 37: Topic number 37 <ch37>

== Section 37.1

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch36, the details of case 37.1.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch36, the details of case 37.1.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch36, the details of case 37.1.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch36, the details of case 37.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 37.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 37a], [1.37], [2.37], [3.37], [row 37b], [4.37], [5.37], [6.37], [row 37c], [7.37], [8.37], [9.37]), caption: [Measurements for chapter 37.]) <tab37>

== Section 37.2

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch36, the details of case 37.2.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch36, the details of case 37.2.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch36, the details of case 37.2.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch36, the details of case 37.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 37.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 37]], caption: [A figure in chapter 37, referenced from @tab37.]) <fig37>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 37.3

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch36, the details of case 37.3.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch36, the details of case 37.3.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch36, the details of case 37.3.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch36, the details of case 37.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 37.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig37

= Chapter 38: Topic number 38 <ch38>

== Section 38.1

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch37, the details of case 38.1.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch37, the details of case 38.1.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch37, the details of case 38.1.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch37, the details of case 38.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 38.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 38a], [1.38], [2.38], [3.38], [row 38b], [4.38], [5.38], [6.38], [row 38c], [7.38], [8.38], [9.38]), caption: [Measurements for chapter 38.]) <tab38>

== Section 38.2

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch37, the details of case 38.2.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch37, the details of case 38.2.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch37, the details of case 38.2.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch37, the details of case 38.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 38.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 38]], caption: [A figure in chapter 38, referenced from @tab38.]) <fig38>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 38.3

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch37, the details of case 38.3.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch37, the details of case 38.3.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch37, the details of case 38.3.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch37, the details of case 38.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 38.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig38

= Chapter 39: Topic number 39 <ch39>

== Section 39.1

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch38, the details of case 39.1.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch38, the details of case 39.1.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch38, the details of case 39.1.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch38, the details of case 39.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 39.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 39a], [1.39], [2.39], [3.39], [row 39b], [4.39], [5.39], [6.39], [row 39c], [7.39], [8.39], [9.39]), caption: [Measurements for chapter 39.]) <tab39>

== Section 39.2

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch38, the details of case 39.2.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch38, the details of case 39.2.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch38, the details of case 39.2.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch38, the details of case 39.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 39.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 39]], caption: [A figure in chapter 39, referenced from @tab39.]) <fig39>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 39.3

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch38, the details of case 39.3.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch38, the details of case 39.3.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch38, the details of case 39.3.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch38, the details of case 39.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 39.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig39

= Chapter 40: Topic number 40 <ch40>

== Section 40.1

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch39, the details of case 40.1.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch39, the details of case 40.1.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch39, the details of case 40.1.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch39, the details of case 40.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 40.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 40a], [1.40], [2.40], [3.40], [row 40b], [4.40], [5.40], [6.40], [row 40c], [7.40], [8.40], [9.40]), caption: [Measurements for chapter 40.]) <tab40>

== Section 40.2

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch39, the details of case 40.2.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch39, the details of case 40.2.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch39, the details of case 40.2.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch39, the details of case 40.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 40.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 40]], caption: [A figure in chapter 40, referenced from @tab40.]) <fig40>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 40.3

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch39, the details of case 40.3.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch39, the details of case 40.3.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch39, the details of case 40.3.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch39, the details of case 40.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 40.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig40

= Chapter 41: Topic number 41 <ch41>

== Section 41.1

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch40, the details of case 41.1.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch40, the details of case 41.1.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch40, the details of case 41.1.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch40, the details of case 41.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 41.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 41a], [1.41], [2.41], [3.41], [row 41b], [4.41], [5.41], [6.41], [row 41c], [7.41], [8.41], [9.41]), caption: [Measurements for chapter 41.]) <tab41>

== Section 41.2

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch40, the details of case 41.2.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch40, the details of case 41.2.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch40, the details of case 41.2.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch40, the details of case 41.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 41.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 41]], caption: [A figure in chapter 41, referenced from @tab41.]) <fig41>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 41.3

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch40, the details of case 41.3.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch40, the details of case 41.3.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch40, the details of case 41.3.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch40, the details of case 41.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 41.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig41

= Chapter 42: Topic number 42 <ch42>

== Section 42.1

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch41, the details of case 42.1.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch41, the details of case 42.1.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch41, the details of case 42.1.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch41, the details of case 42.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 42.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 42a], [1.42], [2.42], [3.42], [row 42b], [4.42], [5.42], [6.42], [row 42c], [7.42], [8.42], [9.42]), caption: [Measurements for chapter 42.]) <tab42>

== Section 42.2

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch41, the details of case 42.2.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch41, the details of case 42.2.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch41, the details of case 42.2.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch41, the details of case 42.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 42.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 42]], caption: [A figure in chapter 42, referenced from @tab42.]) <fig42>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 42.3

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch41, the details of case 42.3.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch41, the details of case 42.3.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch41, the details of case 42.3.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch41, the details of case 42.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 42.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig42

= Chapter 43: Topic number 43 <ch43>

== Section 43.1

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch42, the details of case 43.1.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch42, the details of case 43.1.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch42, the details of case 43.1.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch42, the details of case 43.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 43.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 43a], [1.43], [2.43], [3.43], [row 43b], [4.43], [5.43], [6.43], [row 43c], [7.43], [8.43], [9.43]), caption: [Measurements for chapter 43.]) <tab43>

== Section 43.2

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch42, the details of case 43.2.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch42, the details of case 43.2.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch42, the details of case 43.2.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch42, the details of case 43.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 43.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 43]], caption: [A figure in chapter 43, referenced from @tab43.]) <fig43>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 43.3

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch42, the details of case 43.3.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch42, the details of case 43.3.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch42, the details of case 43.3.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch42, the details of case 43.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 43.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig43

= Chapter 44: Topic number 44 <ch44>

== Section 44.1

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch43, the details of case 44.1.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch43, the details of case 44.1.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch43, the details of case 44.1.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch43, the details of case 44.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 44.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 44a], [1.44], [2.44], [3.44], [row 44b], [4.44], [5.44], [6.44], [row 44c], [7.44], [8.44], [9.44]), caption: [Measurements for chapter 44.]) <tab44>

== Section 44.2

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch43, the details of case 44.2.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch43, the details of case 44.2.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch43, the details of case 44.2.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch43, the details of case 44.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 44.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 44]], caption: [A figure in chapter 44, referenced from @tab44.]) <fig44>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 44.3

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch43, the details of case 44.3.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch43, the details of case 44.3.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch43, the details of case 44.3.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch43, the details of case 44.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 44.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig44

= Chapter 45: Topic number 45 <ch45>

== Section 45.1

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch44, the details of case 45.1.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch44, the details of case 45.1.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch44, the details of case 45.1.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch44, the details of case 45.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 45.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 45a], [1.45], [2.45], [3.45], [row 45b], [4.45], [5.45], [6.45], [row 45c], [7.45], [8.45], [9.45]), caption: [Measurements for chapter 45.]) <tab45>

== Section 45.2

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch44, the details of case 45.2.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch44, the details of case 45.2.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch44, the details of case 45.2.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch44, the details of case 45.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 45.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 45]], caption: [A figure in chapter 45, referenced from @tab45.]) <fig45>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 45.3

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch44, the details of case 45.3.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch44, the details of case 45.3.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch44, the details of case 45.3.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch44, the details of case 45.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 45.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig45

= Chapter 46: Topic number 46 <ch46>

== Section 46.1

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch45, the details of case 46.1.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch45, the details of case 46.1.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch45, the details of case 46.1.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch45, the details of case 46.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 46.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 46a], [1.46], [2.46], [3.46], [row 46b], [4.46], [5.46], [6.46], [row 46c], [7.46], [8.46], [9.46]), caption: [Measurements for chapter 46.]) <tab46>

== Section 46.2

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch45, the details of case 46.2.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch45, the details of case 46.2.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch45, the details of case 46.2.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch45, the details of case 46.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 46.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 46]], caption: [A figure in chapter 46, referenced from @tab46.]) <fig46>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 46.3

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch45, the details of case 46.3.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch45, the details of case 46.3.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch45, the details of case 46.3.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch45, the details of case 46.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 46.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig46

= Chapter 47: Topic number 47 <ch47>

== Section 47.1

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch46, the details of case 47.1.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch46, the details of case 47.1.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch46, the details of case 47.1.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch46, the details of case 47.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 47.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 47a], [1.47], [2.47], [3.47], [row 47b], [4.47], [5.47], [6.47], [row 47c], [7.47], [8.47], [9.47]), caption: [Measurements for chapter 47.]) <tab47>

== Section 47.2

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch46, the details of case 47.2.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch46, the details of case 47.2.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch46, the details of case 47.2.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch46, the details of case 47.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 47.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 47]], caption: [A figure in chapter 47, referenced from @tab47.]) <fig47>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 47.3

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch46, the details of case 47.3.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch46, the details of case 47.3.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch46, the details of case 47.3.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch46, the details of case 47.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 47.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig47

= Chapter 48: Topic number 48 <ch48>

== Section 48.1

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch47, the details of case 48.1.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch47, the details of case 48.1.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch47, the details of case 48.1.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch47, the details of case 48.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 48.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 48a], [1.48], [2.48], [3.48], [row 48b], [4.48], [5.48], [6.48], [row 48c], [7.48], [8.48], [9.48]), caption: [Measurements for chapter 48.]) <tab48>

== Section 48.2

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch47, the details of case 48.2.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch47, the details of case 48.2.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch47, the details of case 48.2.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch47, the details of case 48.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 48.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 48]], caption: [A figure in chapter 48, referenced from @tab48.]) <fig48>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 48.3

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch47, the details of case 48.3.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch47, the details of case 48.3.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch47, the details of case 48.3.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch47, the details of case 48.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 48.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig48

= Chapter 49: Topic number 49 <ch49>

== Section 49.1

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch48, the details of case 49.1.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch48, the details of case 49.1.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch48, the details of case 49.1.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch48, the details of case 49.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 49.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 49a], [1.49], [2.49], [3.49], [row 49b], [4.49], [5.49], [6.49], [row 49c], [7.49], [8.49], [9.49]), caption: [Measurements for chapter 49.]) <tab49>

== Section 49.2

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch48, the details of case 49.2.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch48, the details of case 49.2.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch48, the details of case 49.2.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch48, the details of case 49.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 49.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 49]], caption: [A figure in chapter 49, referenced from @tab49.]) <fig49>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 49.3

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch48, the details of case 49.3.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch48, the details of case 49.3.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch48, the details of case 49.3.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch48, the details of case 49.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 49.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig49

= Chapter 50: Topic number 50 <ch50>

== Section 50.1

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch49, the details of case 50.1.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch49, the details of case 50.1.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch49, the details of case 50.1.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch49, the details of case 50.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 50.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 50a], [1.50], [2.50], [3.50], [row 50b], [4.50], [5.50], [6.50], [row 50c], [7.50], [8.50], [9.50]), caption: [Measurements for chapter 50.]) <tab50>

== Section 50.2

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch49, the details of case 50.2.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch49, the details of case 50.2.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch49, the details of case 50.2.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch49, the details of case 50.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 50.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 50]], caption: [A figure in chapter 50, referenced from @tab50.]) <fig50>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 50.3

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch49, the details of case 50.3.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch49, the details of case 50.3.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch49, the details of case 50.3.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch49, the details of case 50.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 50.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig50

= Chapter 51: Topic number 51 <ch51>

== Section 51.1

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch50, the details of case 51.1.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch50, the details of case 51.1.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch50, the details of case 51.1.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch50, the details of case 51.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 51.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 51a], [1.51], [2.51], [3.51], [row 51b], [4.51], [5.51], [6.51], [row 51c], [7.51], [8.51], [9.51]), caption: [Measurements for chapter 51.]) <tab51>

== Section 51.2

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch50, the details of case 51.2.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch50, the details of case 51.2.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch50, the details of case 51.2.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch50, the details of case 51.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 51.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 51]], caption: [A figure in chapter 51, referenced from @tab51.]) <fig51>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 51.3

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch50, the details of case 51.3.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch50, the details of case 51.3.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch50, the details of case 51.3.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch50, the details of case 51.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 51.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig51

= Chapter 52: Topic number 52 <ch52>

== Section 52.1

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch51, the details of case 52.1.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch51, the details of case 52.1.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch51, the details of case 52.1.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch51, the details of case 52.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 52.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 52a], [1.52], [2.52], [3.52], [row 52b], [4.52], [5.52], [6.52], [row 52c], [7.52], [8.52], [9.52]), caption: [Measurements for chapter 52.]) <tab52>

== Section 52.2

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch51, the details of case 52.2.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch51, the details of case 52.2.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch51, the details of case 52.2.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch51, the details of case 52.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 52.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 52]], caption: [A figure in chapter 52, referenced from @tab52.]) <fig52>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 52.3

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch51, the details of case 52.3.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch51, the details of case 52.3.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch51, the details of case 52.3.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch51, the details of case 52.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 52.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig52

= Chapter 53: Topic number 53 <ch53>

== Section 53.1

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch52, the details of case 53.1.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch52, the details of case 53.1.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch52, the details of case 53.1.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch52, the details of case 53.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 53.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 53a], [1.53], [2.53], [3.53], [row 53b], [4.53], [5.53], [6.53], [row 53c], [7.53], [8.53], [9.53]), caption: [Measurements for chapter 53.]) <tab53>

== Section 53.2

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch52, the details of case 53.2.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch52, the details of case 53.2.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch52, the details of case 53.2.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch52, the details of case 53.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 53.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 53]], caption: [A figure in chapter 53, referenced from @tab53.]) <fig53>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 53.3

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch52, the details of case 53.3.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch52, the details of case 53.3.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch52, the details of case 53.3.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch52, the details of case 53.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 53.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig53

= Chapter 54: Topic number 54 <ch54>

== Section 54.1

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch53, the details of case 54.1.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch53, the details of case 54.1.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch53, the details of case 54.1.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch53, the details of case 54.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 54.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 54a], [1.54], [2.54], [3.54], [row 54b], [4.54], [5.54], [6.54], [row 54c], [7.54], [8.54], [9.54]), caption: [Measurements for chapter 54.]) <tab54>

== Section 54.2

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch53, the details of case 54.2.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch53, the details of case 54.2.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch53, the details of case 54.2.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch53, the details of case 54.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 54.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 54]], caption: [A figure in chapter 54, referenced from @tab54.]) <fig54>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 54.3

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch53, the details of case 54.3.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch53, the details of case 54.3.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch53, the details of case 54.3.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch53, the details of case 54.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 54.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig54

= Chapter 55: Topic number 55 <ch55>

== Section 55.1

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch54, the details of case 55.1.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch54, the details of case 55.1.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch54, the details of case 55.1.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch54, the details of case 55.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 55.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 55a], [1.55], [2.55], [3.55], [row 55b], [4.55], [5.55], [6.55], [row 55c], [7.55], [8.55], [9.55]), caption: [Measurements for chapter 55.]) <tab55>

== Section 55.2

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch54, the details of case 55.2.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch54, the details of case 55.2.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch54, the details of case 55.2.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch54, the details of case 55.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 55.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 55]], caption: [A figure in chapter 55, referenced from @tab55.]) <fig55>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 55.3

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch54, the details of case 55.3.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch54, the details of case 55.3.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch54, the details of case 55.3.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch54, the details of case 55.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 55.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig55

= Chapter 56: Topic number 56 <ch56>

== Section 56.1

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch55, the details of case 56.1.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch55, the details of case 56.1.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch55, the details of case 56.1.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch55, the details of case 56.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 56.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 56a], [1.56], [2.56], [3.56], [row 56b], [4.56], [5.56], [6.56], [row 56c], [7.56], [8.56], [9.56]), caption: [Measurements for chapter 56.]) <tab56>

== Section 56.2

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch55, the details of case 56.2.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch55, the details of case 56.2.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch55, the details of case 56.2.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch55, the details of case 56.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 56.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 56]], caption: [A figure in chapter 56, referenced from @tab56.]) <fig56>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 56.3

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch55, the details of case 56.3.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch55, the details of case 56.3.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch55, the details of case 56.3.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch55, the details of case 56.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 56.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig56

= Chapter 57: Topic number 57 <ch57>

== Section 57.1

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch56, the details of case 57.1.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch56, the details of case 57.1.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch56, the details of case 57.1.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch56, the details of case 57.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 57.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 57a], [1.57], [2.57], [3.57], [row 57b], [4.57], [5.57], [6.57], [row 57c], [7.57], [8.57], [9.57]), caption: [Measurements for chapter 57.]) <tab57>

== Section 57.2

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch56, the details of case 57.2.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch56, the details of case 57.2.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch56, the details of case 57.2.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch56, the details of case 57.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 57.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 57]], caption: [A figure in chapter 57, referenced from @tab57.]) <fig57>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 57.3

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch56, the details of case 57.3.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch56, the details of case 57.3.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch56, the details of case 57.3.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch56, the details of case 57.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 57.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig57

= Chapter 58: Topic number 58 <ch58>

== Section 58.1

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch57, the details of case 58.1.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch57, the details of case 58.1.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch57, the details of case 58.1.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch57, the details of case 58.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 58.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 58a], [1.58], [2.58], [3.58], [row 58b], [4.58], [5.58], [6.58], [row 58c], [7.58], [8.58], [9.58]), caption: [Measurements for chapter 58.]) <tab58>

== Section 58.2

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch57, the details of case 58.2.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch57, the details of case 58.2.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch57, the details of case 58.2.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch57, the details of case 58.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 58.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 58]], caption: [A figure in chapter 58, referenced from @tab58.]) <fig58>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 58.3

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch57, the details of case 58.3.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch57, the details of case 58.3.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch57, the details of case 58.3.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch57, the details of case 58.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 58.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig58

= Chapter 59: Topic number 59 <ch59>

== Section 59.1

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch58, the details of case 59.1.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch58, the details of case 59.1.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch58, the details of case 59.1.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch58, the details of case 59.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 59.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 59a], [1.59], [2.59], [3.59], [row 59b], [4.59], [5.59], [6.59], [row 59c], [7.59], [8.59], [9.59]), caption: [Measurements for chapter 59.]) <tab59>

== Section 59.2

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch58, the details of case 59.2.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch58, the details of case 59.2.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch58, the details of case 59.2.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch58, the details of case 59.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 59.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 59]], caption: [A figure in chapter 59, referenced from @tab59.]) <fig59>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 59.3

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch58, the details of case 59.3.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch58, the details of case 59.3.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch58, the details of case 59.3.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch58, the details of case 59.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 59.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig59

= Chapter 60: Topic number 60 <ch60>

== Section 60.1

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch59, the details of case 60.1.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch59, the details of case 60.1.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch59, the details of case 60.1.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch59, the details of case 60.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 60.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 60a], [1.60], [2.60], [3.60], [row 60b], [4.60], [5.60], [6.60], [row 60c], [7.60], [8.60], [9.60]), caption: [Measurements for chapter 60.]) <tab60>

== Section 60.2

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch59, the details of case 60.2.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch59, the details of case 60.2.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch59, the details of case 60.2.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch59, the details of case 60.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 60.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 60]], caption: [A figure in chapter 60, referenced from @tab60.]) <fig60>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 60.3

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch59, the details of case 60.3.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch59, the details of case 60.3.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch59, the details of case 60.3.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch59, the details of case 60.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 60.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig60

= Chapter 61: Topic number 61 <ch61>

== Section 61.1

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch60, the details of case 61.1.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch60, the details of case 61.1.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch60, the details of case 61.1.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch60, the details of case 61.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 61.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 61a], [1.61], [2.61], [3.61], [row 61b], [4.61], [5.61], [6.61], [row 61c], [7.61], [8.61], [9.61]), caption: [Measurements for chapter 61.]) <tab61>

== Section 61.2

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch60, the details of case 61.2.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch60, the details of case 61.2.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch60, the details of case 61.2.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch60, the details of case 61.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 61.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 61]], caption: [A figure in chapter 61, referenced from @tab61.]) <fig61>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 61.3

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch60, the details of case 61.3.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch60, the details of case 61.3.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch60, the details of case 61.3.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch60, the details of case 61.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 61.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig61

= Chapter 62: Topic number 62 <ch62>

== Section 62.1

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch61, the details of case 62.1.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch61, the details of case 62.1.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch61, the details of case 62.1.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch61, the details of case 62.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 62.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 62a], [1.62], [2.62], [3.62], [row 62b], [4.62], [5.62], [6.62], [row 62c], [7.62], [8.62], [9.62]), caption: [Measurements for chapter 62.]) <tab62>

== Section 62.2

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch61, the details of case 62.2.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch61, the details of case 62.2.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch61, the details of case 62.2.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch61, the details of case 62.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 62.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 62]], caption: [A figure in chapter 62, referenced from @tab62.]) <fig62>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 62.3

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch61, the details of case 62.3.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch61, the details of case 62.3.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch61, the details of case 62.3.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch61, the details of case 62.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 62.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig62

= Chapter 63: Topic number 63 <ch63>

== Section 63.1

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch62, the details of case 63.1.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch62, the details of case 63.1.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch62, the details of case 63.1.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch62, the details of case 63.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 63.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 63a], [1.63], [2.63], [3.63], [row 63b], [4.63], [5.63], [6.63], [row 63c], [7.63], [8.63], [9.63]), caption: [Measurements for chapter 63.]) <tab63>

== Section 63.2

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch62, the details of case 63.2.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch62, the details of case 63.2.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch62, the details of case 63.2.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch62, the details of case 63.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 63.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 63]], caption: [A figure in chapter 63, referenced from @tab63.]) <fig63>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 63.3

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch62, the details of case 63.3.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch62, the details of case 63.3.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch62, the details of case 63.3.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch62, the details of case 63.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 63.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig63

= Chapter 64: Topic number 64 <ch64>

== Section 64.1

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch63, the details of case 64.1.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch63, the details of case 64.1.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch63, the details of case 64.1.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch63, the details of case 64.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 64.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 64a], [1.64], [2.64], [3.64], [row 64b], [4.64], [5.64], [6.64], [row 64c], [7.64], [8.64], [9.64]), caption: [Measurements for chapter 64.]) <tab64>

== Section 64.2

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch63, the details of case 64.2.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch63, the details of case 64.2.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch63, the details of case 64.2.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch63, the details of case 64.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 64.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 64]], caption: [A figure in chapter 64, referenced from @tab64.]) <fig64>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 64.3

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch63, the details of case 64.3.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch63, the details of case 64.3.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch63, the details of case 64.3.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch63, the details of case 64.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 64.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig64

= Chapter 65: Topic number 65 <ch65>

== Section 65.1

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch64, the details of case 65.1.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch64, the details of case 65.1.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch64, the details of case 65.1.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch64, the details of case 65.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 65.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 65a], [1.65], [2.65], [3.65], [row 65b], [4.65], [5.65], [6.65], [row 65c], [7.65], [8.65], [9.65]), caption: [Measurements for chapter 65.]) <tab65>

== Section 65.2

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch64, the details of case 65.2.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch64, the details of case 65.2.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch64, the details of case 65.2.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch64, the details of case 65.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 65.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 65]], caption: [A figure in chapter 65, referenced from @tab65.]) <fig65>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 65.3

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch64, the details of case 65.3.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch64, the details of case 65.3.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch64, the details of case 65.3.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch64, the details of case 65.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 65.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig65

= Chapter 66: Topic number 66 <ch66>

== Section 66.1

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch65, the details of case 66.1.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch65, the details of case 66.1.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch65, the details of case 66.1.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch65, the details of case 66.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 66.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 66a], [1.66], [2.66], [3.66], [row 66b], [4.66], [5.66], [6.66], [row 66c], [7.66], [8.66], [9.66]), caption: [Measurements for chapter 66.]) <tab66>

== Section 66.2

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch65, the details of case 66.2.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch65, the details of case 66.2.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch65, the details of case 66.2.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch65, the details of case 66.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 66.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 66]], caption: [A figure in chapter 66, referenced from @tab66.]) <fig66>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 66.3

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch65, the details of case 66.3.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch65, the details of case 66.3.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch65, the details of case 66.3.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch65, the details of case 66.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 66.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig66

= Chapter 67: Topic number 67 <ch67>

== Section 67.1

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch66, the details of case 67.1.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch66, the details of case 67.1.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch66, the details of case 67.1.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch66, the details of case 67.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 67.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 67a], [1.67], [2.67], [3.67], [row 67b], [4.67], [5.67], [6.67], [row 67c], [7.67], [8.67], [9.67]), caption: [Measurements for chapter 67.]) <tab67>

== Section 67.2

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch66, the details of case 67.2.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch66, the details of case 67.2.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch66, the details of case 67.2.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch66, the details of case 67.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 67.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 67]], caption: [A figure in chapter 67, referenced from @tab67.]) <fig67>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 67.3

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch66, the details of case 67.3.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch66, the details of case 67.3.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch66, the details of case 67.3.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch66, the details of case 67.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 67.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig67

= Chapter 68: Topic number 68 <ch68>

== Section 68.1

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch67, the details of case 68.1.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch67, the details of case 68.1.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch67, the details of case 68.1.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch67, the details of case 68.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 68.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 68a], [1.68], [2.68], [3.68], [row 68b], [4.68], [5.68], [6.68], [row 68c], [7.68], [8.68], [9.68]), caption: [Measurements for chapter 68.]) <tab68>

== Section 68.2

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch67, the details of case 68.2.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch67, the details of case 68.2.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch67, the details of case 68.2.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch67, the details of case 68.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 68.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 68]], caption: [A figure in chapter 68, referenced from @tab68.]) <fig68>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 68.3

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch67, the details of case 68.3.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch67, the details of case 68.3.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch67, the details of case 68.3.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch67, the details of case 68.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 68.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig68

= Chapter 69: Topic number 69 <ch69>

== Section 69.1

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch68, the details of case 69.1.0 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch68, the details of case 69.1.1 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch68, the details of case 69.1.2 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch68, the details of case 69.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 69.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 69a], [1.69], [2.69], [3.69], [row 69b], [4.69], [5.69], [6.69], [row 69c], [7.69], [8.69], [9.69]), caption: [Measurements for chapter 69.]) <tab69>

== Section 69.2

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch68, the details of case 69.2.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch68, the details of case 69.2.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch68, the details of case 69.2.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch68, the details of case 69.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 69.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 69]], caption: [A figure in chapter 69, referenced from @tab69.]) <fig69>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 69.3

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch68, the details of case 69.3.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch68, the details of case 69.3.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch68, the details of case 69.3.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch68, the details of case 69.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 69.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig69

= Chapter 70: Topic number 70 <ch70>

== Section 70.1

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch69, the details of case 70.1.0 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch69, the details of case 70.1.1 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch69, the details of case 70.1.2 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch69, the details of case 70.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 70.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 70a], [1.70], [2.70], [3.70], [row 70b], [4.70], [5.70], [6.70], [row 70c], [7.70], [8.70], [9.70]), caption: [Measurements for chapter 70.]) <tab70>

== Section 70.2

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch69, the details of case 70.2.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch69, the details of case 70.2.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch69, the details of case 70.2.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch69, the details of case 70.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 70.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 70]], caption: [A figure in chapter 70, referenced from @tab70.]) <fig70>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 70.3

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch69, the details of case 70.3.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch69, the details of case 70.3.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch69, the details of case 70.3.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch69, the details of case 70.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 70.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig70

= Chapter 71: Topic number 71 <ch71>

== Section 71.1

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch70, the details of case 71.1.0 matter.

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch70, the details of case 71.1.1 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch70, the details of case 71.1.2 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch70, the details of case 71.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 71.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 71a], [1.71], [2.71], [3.71], [row 71b], [4.71], [5.71], [6.71], [row 71c], [7.71], [8.71], [9.71]), caption: [Measurements for chapter 71.]) <tab71>

== Section 71.2

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch70, the details of case 71.2.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch70, the details of case 71.2.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch70, the details of case 71.2.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch70, the details of case 71.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 71.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 71]], caption: [A figure in chapter 71, referenced from @tab71.]) <fig71>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 71.3

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch70, the details of case 71.3.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch70, the details of case 71.3.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch70, the details of case 71.3.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch70, the details of case 71.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 71.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig71

= Chapter 72: Topic number 72 <ch72>

== Section 72.1

When a document grows beyond a few pages, the cost of recompiling after every edit becomes visible. Incremental computation, where unchanged parts of the document are reused, turns a multi-hundred-millisecond job into something that feels immediate. The trick is to cache at the right granularity: too coarse and nothing is reused, too fine and bookkeeping dominates. As discussed in @ch71, the details of case 72.1.0 matter.

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch71, the details of case 72.1.1 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch71, the details of case 72.1.2 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch71, the details of case 72.1.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 72.1.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(table(columns: 4, [*Name*], [*Alpha*], [*Beta*], [*Gamma*], [row 72a], [1.72], [2.72], [3.72], [row 72b], [4.72], [5.72], [6.72], [row 72c], [7.72], [8.72], [9.72]), caption: [Measurements for chapter 72.]) <tab72>

== Section 72.2

Consider a researcher drafting a long report. She writes a paragraph, glances at the preview, adjusts a figure caption, and moves on. Each of those small actions should produce feedback within a frame or two. Anything slower breaks the flow and trains the writer to stop looking at the preview altogether. As discussed in @ch71, the details of case 72.2.0 matter.

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch71, the details of case 72.2.1 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch71, the details of case 72.2.2 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch71, the details of case 72.2.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 72.2.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

#figure(rect(width: 70%, height: 3cm, fill: rgb("#dde8ff"))[#align(center + horizon)[Placeholder figure 72]], caption: [A figure in chapter 72, referenced from @tab72.]) <fig72>

#showybox(title: "Note", frame: (border-color: blue))[This box comes from a downloaded package and carries a short remark.]

== Section 72.3

Numbers matter more than intuition here. A compile that takes eighty milliseconds on a laptop may take three times as long on a tablet, and a preview path that allocates a megabyte per keystroke will eventually be noticed by the memory allocator. Measuring both ends of the pipeline, compile and display, is the only honest way to compare designs. As discussed in @ch71, the details of case 72.3.0 matter.

Typography also rewards patience. Kerning pairs, ligatures, and optical margins are invisible when done well and glaring when done badly. The embedded fonts that ship with the compiler cover the common cases, but a serious editor must also be able to reach the fonts installed on the user's system, which on mobile platforms means asking the operating system for file locations. As discussed in @ch71, the details of case 72.3.1 matter.

Packages extend the language without enlarging the core. A box with a title and a coloured frame, a diagram, a bibliography style: each is a small library fetched once and cached on disk. On a desktop the cache lives in a well-known directory; on a sandboxed device the host application must choose and supply the location explicitly. As discussed in @ch71, the details of case 72.3.2 matter.

The history of typesetting is a story of constraints. Early printers worked with movable type cast in lead, and every decision about line length, hyphenation and spacing was made by a human hand. Modern systems encode many of those decisions in algorithms, but the underlying goal remains the same: a page that is easy to read. As discussed in @ch71, the details of case 72.3.3 matter.

Inline math such as $a^2 + b^2 = c^2$ and $sum_(i=1)^n i = (n(n+1))/2$ appears in the text of section 72.3.

$ integral_0^oo e^(-x^2) dif x = sqrt(pi)/2 quad "and" quad lim_(n -> oo) (1 + 1/n)^n = e $

+ First numbered item with some words
+ Second numbered item
+ Third numbered item referring to @fig72
