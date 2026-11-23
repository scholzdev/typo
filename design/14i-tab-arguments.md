# 14i. Tab between call arguments

Tab jumps to the next argument of the call the caret is in, Shift-Tab to the previous one. In
`#table(columns: 3, [a], [], [c])` it moves cell to cell; in `#figure(image("x.png"), caption: [])` from the image to
the caption. Completion snippets (`figure(${}, caption: ${})`) reach their later placeholders the same way.

## Behaviour (rules in order)
The completion popup is handled first (Tab accepts). Then, in `textView(_:doCommandBy:)`, `insertTab:` and
`insertBacktab:` ask `Buffer.tabJump`; nil means the normal key action (a tab character, default back-tab).
0. Caret in a line's indentation (only blanks before it, including column 0): nil, so Tab indents (`]` on its own line moves
   right). Shift-Tab there outdents the line by one unit (one leading tab, or up to 4 spaces) as one undo step
   (`Buffer.outdentAtCaret`, caret stays after the same text); nothing to outdent: normal back-tab. Only a caret after text jumps.
1. Caret line is a list, enum or term item (`- `, `+ `, `1. `, `/ `): nil, so Tab keeps nesting lists.
2. The innermost argument list with at least 2 arguments around the caret (`tb_syntax_args`, `min_targets = 2`). A single
   argument `#block[ prose ]` keeps normal Tab; `[#emph[x]]` inside a table jumps to the next cell. The callee name is not inside.
3. Forward: the target after the one holding the caret. At the last argument the enclosing list is tried from the end of
   the call; with none, the caret goes right after the call's closing delimiter.
   Backward: the previous target; at the first argument the enclosing list's previous target, else nil.
4. No argument list around the caret: nil.

Targets: content block = its inside (empty `[]` puts the caret there); `name: value` = the value (block value: its inside);
anything else = the expression; trailing blocks (`f(a)[b]`) count. A stray comma (an unfilled snippet `f(, x: )`) is an
empty argument and an unfinished `name:` is an empty target after the colon, so snippets work before they are filled in.
The selection is set programmatically (no preview sync) and scrolled into view.

## Limits
Math, strings and comments are not special-cased: an argument list is found by the syntax tree only. Arguments of
unfinished calls (`#table(columns: 2, [a],`) work while the parse recovers. No snippet-specific state: Tab-ing works
from any caret position, not only straight after accepting a completion.

## Tests (`TabJumpTests`)
Table cells forward and back incl. empty `[]`; named value selected; figure image to caption; nested `[#emph[x]]`; last cell
caret after `)`; Shift-Tab at the first argument nil; `#block[- a]`, callee name, list line, plain text nil; unfinished call,
strings and comments in arguments; indentation Tab nil (column 0, spaces, table row on its own line), Shift-Tab outdent (tab, spaces, none); snippet `figure(${}, caption: ${})` first placeholder then Tab to caption.
