import Foundation
import TypstEngine
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// The parameter name shown before a positional argument; display only, never part of the text.
public struct InlayHint: Equatable, Sendable {
    /// Start of the argument (UTF-16).
    public let offset: Int
    /// For example `base:`.
    public let label: String
}

public enum InlayHints {
    // shortcut: only the first 300 arguments of a file get hints, upgrade to visible-range hints when files get this large
    static let maxCandidates = 300

    /// Slightly smaller than the editor font; the app draws with exactly this font so the gap fits the label.
    @MainActor public static var font: PlatformFont { .systemFont(ofSize: Highlighter.fontSize - 2) }
    /// Space between the gap's edges and the label's background, and between the background and the label.
    public static let margin: CGFloat = 2, padding: CGFloat = 3

    /// The kern gap a label needs.
    @MainActor public static func gap(_ label: String) -> CGFloat {
        ceil((label as NSString).size(withAttributes: [.font: font]).width) + 2 * (margin + padding)
    }

    /// Positional arguments of every call, as the syntax sees them: not named, not spread (`..x`), not a content block,
    /// and not at the start of a line. Only calls with at least two such arguments count: a lone one is obvious, and
    /// for overloaded built-ins like `rgb("#fff")` its parameter would be wrong (`red`). Each range is one argument's text.
    static func candidates(in text: String, syntax: SyntaxMirror) -> [NSRange] {
        let ns = text as NSString
        var out: [NSRange] = []
        for s in syntax.spans(in: NSRange(location: 0, length: ns.length)) where s.tag == .function {
            let paren = NSMaxRange(s.range)
            // A show-rule selector like `heading` is followed by `:`, not `(`; a list found for a later position is another call's.
            guard paren < ns.length, ns.character(at: paren) == 0x28,
                  let (whole, targets) = syntax.args(at: paren + 1, minTargets: 1), whole.location == paren else { continue }
            let positional = targets.filter { t in
                guard t.length > 0, !ns.substring(with: t).hasPrefix("..") else { return false }
                var i = t.location - 1
                while i > paren, CharacterSet.whitespacesAndNewlines.contains(Unicode.Scalar(ns.character(at: i))!) { i -= 1 }
                return [0x28, 0x2C].contains(ns.character(at: i))      // after `(` or `,`; `:` is named, `[` content
            }
            guard positional.count > 1 else { continue }
            out += positional.filter { ![0x0A, 0x0D].contains(ns.character(at: $0.location - 1)) }
        }
        return out
    }

    /// The label for an argument whose signature help (asked at its start) is `help`, nil where a hint would be noise.
    static func label(argument: String, help: SignatureHelp?) -> String? {
        guard let help, let p = help.activeParameter, p.positional, !p.variadic, !p.name.isEmpty, p.name != "_",
              help.params.filter({ $0.positional && !$0.variadic }).count > 1, argument != p.name else { return nil }
        return p.name + ":"
    }
}

extension Project {
    /// Hints of `file` mapped through the edits since they were computed; empty while hints are off.
    public func inlayHints(in file: RelPath) -> [InlayHint] {
        guard inlayHintsEnabled, let inlay, let hints = inlay.hints[file] else { return [] }
        // The character before the argument: typing at the argument's start keeps the hint before the new text.
        return hints.compactMap { h in
            log.map(NSRange(location: h.offset - 1, length: 1), in: file, from: inlay.seq).map { InlayHint(offset: $0.location + 1, label: h.label) }
        }
    }

    /// Reruns the hints 600 ms after the last compile; a newer call supersedes a pending or running one.
    func scheduleInlayHints() {
        inlayTask?.cancel()
        guard inlayHintsEnabled else { return }
        inlayTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.runInlayHints()
        }
    }

    /// Asks the signature at each positional argument of every open Typst file, one query at a time.
    func runInlayHints() async {
        let seq = lastRecordedSeq
        inflightRequests.append(seq)        // keeps the edits after `seq` in the log until the hints are stored
        defer {
            inflightRequests.remove(at: inflightRequests.firstIndex(of: seq)!)
            trimLog()
        }
        // Every file's candidates as of `seq`, before the first suspension.
        let work = buffers.values.filter(\.isTypst).map { b in
            (b.path, b.storage.string as NSString, InlayHints.candidates(in: b.storage.string, syntax: b.syntax).prefix(InlayHints.maxCandidates))
        }
        var found: [RelPath: [InlayHint]] = [:]
        for (path, text, candidates) in work {
            var hints: [InlayHint] = []
            for c in candidates {
                guard !Task.isCancelled, inlayHintsEnabled else { return }
                // Each query reads the current text, so the offset follows edits made while earlier queries ran.
                guard let now = log.map(NSRange(location: c.location - 1, length: 1), in: path, from: seq) else { continue }
                let help = await signatureHelp(in: path, at: now.location + 1)
                if let label = InlayHints.label(argument: text.substring(with: c), help: help) {
                    hints.append(InlayHint(offset: c.location, label: label))
                }
            }
            found[path] = hints
        }
        guard !Task.isCancelled, inlayHintsEnabled else { return }
        inlay = (seq, found)
        syncAllKerns()
    }

    /// One layout pass per buffer instead of one per changed gap.
    func syncAllKerns() {
        for b in buffers.values {
            b.storage.beginEditing()
            b.syncKerns()
            b.storage.endEditing()
        }
    }
}
