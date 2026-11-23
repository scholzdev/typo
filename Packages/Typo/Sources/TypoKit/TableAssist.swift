import Foundation

/// The table editor's Intelligence button: what is sent to a model, and reading its answer back into the table.
public enum TableAssist {
    public static func system(callee: String) -> String {
        """
        You edit one Typst table. You get the table's current markup and a requested change.
        Answer with the whole table after the change: exactly one `\(callee)(...)` call in a ```typst code block, nothing else in the block.
        - Write `\(callee)(` without a leading `#`; use `\(callee).header`, `\(callee).cell` and `\(callee).hline` for the header, merged cells and lines.
        - Keep the `columns:` argument in the same style (a number or an array of widths) unless the change needs other columns.
        - Keep the other arguments (align, stroke, fill, inset …) unless asked to change them.
        - Keep cell markup intact: labels, references, math, emphasis, function calls and escapes stay as written.
        - Write every number in math mode: `[$2023$]`, `[$3.14$]`, `[$-12$]`, `[$1.76$ T]`, `[$12$ kg]`, `[$45$ %]` (a unit, suffix or word stays outside the dollars). Numbers already in math stay as written. Years count as numbers too.
        - Write content cells in square brackets; escape `[`, `]`, `#`, `$`, `*`, `_`, `@`, `<` and `\\` with a backslash where they are plain text.
        - Never wrap the table in `figure(...)` and never add a caption or label unless asked.
        After the code block, write one short line that says what you changed, such as "Sorted 12 rows by Price."
        """
    }

    /// The user message: the table, its caption, the selection (A1 names as the grid shows them) and the request.
    public static func message(markup: String, caption: String, selection: String?, request: String) -> String {
        var parts = ["The table:\n```typst\n\(markup)\n```"]
        if !caption.isEmpty { parts.append("Its caption: \(caption)") }
        if let selection { parts.append("Selected cells: \(selection)") }
        parts.append("Change: \(request)")
        return parts.joined(separator: "\n\n")
    }

    /// The table code of a reply (its first code block, else the whole reply) and the line after the block, if any.
    public static func reply(_ text: String) -> (code: String, summary: String?) {
        guard let fence = text.firstMatch(of: /```[A-Za-z]*[ \t]*\n((?s:.*?))```/) else {
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }
        let after = text[fence.range.upperBound...].split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
        return (String(fence.output.1).trimmingCharacters(in: .whitespacesAndNewlines), after)
    }

    /// `model` with the reply's table content, or nil when the reply holds no table of the same kind that the editor can read.
    public static func apply(_ text: String, to model: TableModel) -> (model: TableModel, summary: String?)? {
        let r = reply(text)
        let source = r.code.hasPrefix("#") ? r.code : "#" + r.code
        let at = (source as NSString).range(of: "\(model.callee)(")
        guard at.location != NSNotFound, case .table(let new)? = TableModel.lookup(in: source, at: at.location + 1),
              new.callee == model.callee else { return nil }       // verbatim cells and lines name the callee
        return (model.replacingContent(with: new), r.summary)
    }
}

extension TableModel {
    /// The cells, columns, lines and arguments of `other`, written where this table is (same range, callee and figure).
    public func replacingContent(with other: TableModel) -> TableModel {
        var m = self
        m.columns = other.columns
        m.header = other.header
        m.headerArgs = other.headerArgs
        m.rows = other.rows
        m.rules = other.rules
        m.slots = other.slots
        return m
    }
}
