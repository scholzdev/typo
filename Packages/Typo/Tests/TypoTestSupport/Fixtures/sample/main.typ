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
