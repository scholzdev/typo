import Foundation

/// What Xcode's Vim capsule in the editor's bottom bar shows: the mode ("Vim", "Insert", "Visual"), or the
/// command being typed ("Delete…", "Change inside…") with the keys that may follow.
public struct VimBadge: Equatable, Sendable {
    public enum Tone: Equatable, Sendable { case normal, insert, visual, delete, change, other, error }
    public struct Hint: Equatable, Sendable { public let key: String; public let label: String }

    public let title: String
    public let tone: Tone
    public let hints: [Hint]

    static let motions: [Hint] = [.init(key: "w", label: "word"), .init(key: "e", label: "end of word"), .init(key: "b", label: "back"),
                                  .init(key: "$", label: "end of line"), .init(key: "0", label: "line start"), .init(key: "j", label: "line down"),
                                  .init(key: "i", label: "inside…"), .init(key: "a", label: "around…")]
    static let objects: [Hint] = [.init(key: "w", label: "word"), .init(key: "`", label: "backquote"), .init(key: "'", label: "single quote"),
                                  .init(key: "\"", label: "double-quote"), .init(key: "[", label: "square bracket"), .init(key: "(", label: "parenthesis"),
                                  .init(key: "{", label: "brace"), .init(key: "<", label: "angle bracket"), .init(key: "p", label: "paragraph")]
    static let registers: [Hint] = [.init(key: "a-z", label: "named (A-Z appends)"), .init(key: "0", label: "last yank"), .init(key: "1-9", label: "delete history"),
                                    .init(key: "-", label: "small delete"), .init(key: "_", label: "black hole"), .init(key: "+", label: "clipboard")]
    static let letter = [Hint(key: "a-z", label: "a name")]
    static let gMotions: [Hint] = [.init(key: "g", label: "first line"), .init(key: "e", label: "end of previous word"), .init(key: "j", label: "line down"),
                                   .init(key: "k", label: "line up"), .init(key: "u", label: "lowercase…"), .init(key: "U", label: "uppercase…"),
                                   .init(key: "~", label: "toggle case…"), .init(key: "v", label: "reselect")]
}

extension VimState {
    /// The badge for the current mode and pending keys; `message` (an error or a note) wins.
    public func badge(message: String? = nil) -> VimBadge {
        if let message { return VimBadge(title: message, tone: .error, hints: []) }
        let rec = recording.map { " · Recording @" + String($0.reg) } ?? ""
        switch mode {
        case .insert: return VimBadge(title: "Insert" + rec, tone: .insert, hints: [])
        case .commandLine: return VimBadge(title: String(cmdPrefix) + cmdText, tone: .other, hints: [])
        case .visual, .visualLine, .visualBlock, .normal, .operatorPending:
            let base = mode == .visual ? "Visual" : mode == .visualLine ? "Visual Line" : mode == .visualBlock ? "Visual Block" : recording == nil ? "Vim" : "Recording"
            let suffix = mode == .normal || recording == nil ? "" : rec
            var keys = Array(pending.drop { $0.isNumber && $0 != "0" })      // the count does not change the meaning
            if keys.first == "\"" {
                guard keys.count > 2 else { return VimBadge(title: keys.count == 1 ? "Register…" : "Register \"\(keys[1])…", tone: .other, hints: keys.count == 1 ? VimBadge.registers : []) }
                keys.removeFirst(2)
            }
            guard let first = keys.first else { return VimBadge(title: (recording != nil && !isVisual ? "Recording @" + String(recording!.reg) : base) + suffix, tone: isVisual ? .visual : .normal, hints: []) }
            let ops: [Character: (String, VimBadge.Tone)] = ["d": ("Delete", .delete), "c": ("Change", .change), "y": ("Yank", .other),
                                                             ">": ("Indent", .other), "<": ("Outdent", .other)]
            if first == "g", keys.count == 2, "uU~".contains(keys[1]) {
                let name = keys[1] == "u" ? "Lowercase" : keys[1] == "U" ? "Uppercase" : "Toggle case"
                return VimBadge(title: name + "…", tone: .other, hints: VimBadge.motions)
            }
            if let (name, tone) = ops[first] {
                let rest = keys.dropFirst().drop { $0.isNumber }
                switch rest.first {
                case "i": return VimBadge(title: "\(name) inside…", tone: tone, hints: VimBadge.objects)
                case "a": return VimBadge(title: "\(name) around…", tone: tone, hints: VimBadge.objects)
                case "f", "t", "F", "T": return VimBadge(title: "\(name) to…", tone: tone, hints: [.init(key: "", label: "a character")])
                default: return VimBadge(title: "\(name)…", tone: tone, hints: isVisual ? [] : VimBadge.motions)
                }
            }
            switch first {
            case "f", "F": return VimBadge(title: "Find…", tone: .other, hints: [.init(key: "", label: "a character")])
            case "t", "T": return VimBadge(title: "Till…", tone: .other, hints: [.init(key: "", label: "a character")])
            case "r": return VimBadge(title: "Replace…", tone: .other, hints: [.init(key: "", label: "a character")])
            case "g": return VimBadge(title: "Go…", tone: .other, hints: VimBadge.gMotions)
            case "m": return VimBadge(title: "Set mark…", tone: .other, hints: VimBadge.letter)
            case "'": return VimBadge(title: "Go to mark line…", tone: .other, hints: VimBadge.letter)
            case "`": return VimBadge(title: "Go to mark…", tone: .other, hints: VimBadge.letter)
            case "q": return VimBadge(title: "Record macro…", tone: .other, hints: VimBadge.letter)
            case "@": return VimBadge(title: "Play macro…", tone: .other, hints: VimBadge.letter + [.init(key: "@", label: "the last one")])
            case "z": return VimBadge(title: "Scroll…", tone: .other, hints: [.init(key: "z", label: "center"), .init(key: "t", label: "top"), .init(key: "b", label: "bottom")])
            case "i" where isVisual, "a" where isVisual: return VimBadge(title: first == "i" ? "Select inside…" : "Select around…", tone: .visual, hints: VimBadge.objects)
            default: return VimBadge(title: base + " " + String(keys), tone: isVisual ? .visual : .normal, hints: [])
            }
        }
    }
}
