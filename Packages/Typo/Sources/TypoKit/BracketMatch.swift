import Foundation
import TypstEngine

public enum BracketMatch {
    private static let pairs: [unichar: unichar] = [0x28: 0x29, 0x5B: 0x5D, 0x7B: 0x7D]
    private static let openers: [unichar: unichar] = Dictionary(uniqueKeysWithValues: pairs.map { ($0.value, $0.key) })

    /// The bracket pair next to `caret` (before it, else after it); brackets in strings, raw text and comments don't count.
    public static func pair(in text: NSString, caret: Int, mode: (Int) -> SyntaxMode, limit: Int = 20_000) -> (NSRange, NSRange)? {
        for i in [caret - 1, caret] where i >= 0 && i < text.length {
            let c = text.character(at: i)
            guard pairs[c] != nil || openers[c] != nil, mode(i + 1) != .text else { continue }
            if let j = match(text, from: i, mode: mode, limit: limit) {
                let a = NSRange(location: min(i, j), length: 1), b = NSRange(location: max(i, j), length: 1)
                return (a, b)
            }
        }
        return nil
    }

    /// Every counted bracket with its nesting depth (0 = outermost), for rainbow brackets; a closer that matches no opener gets -1.
    public static func depths(in text: NSString, mode: (Int) -> SyntaxMode) -> [(location: Int, depth: Int)] {
        var chars = [unichar](repeating: 0, count: text.length)
        text.getCharacters(&chars, range: NSRange(location: 0, length: text.length))
        var stack: [unichar] = [], out: [(location: Int, depth: Int)] = []
        for (i, c) in chars.enumerated() {
            let closer = pairs[c]
            guard closer != nil || openers[c] != nil, mode(i + 1) != .text else { continue }
            if let closer {
                out.append((i, stack.count))
                stack.append(closer)
            } else if stack.last == c {
                stack.removeLast()
                out.append((i, stack.count))
            } else {
                out.append((i, -1))
            }
        }
        return out
    }

    private static func match(_ text: NSString, from i: Int, mode: (Int) -> SyntaxMode, limit: Int) -> Int? {
        let c = text.character(at: i)
        let forward = pairs[c] != nil
        var stack = [forward ? pairs[c]! : openers[c]!]
        var j = i, scanned = 0
        while scanned < limit {
            j += forward ? 1 : -1
            scanned += 1
            guard j >= 0, j < text.length else { return nil }
            let d = text.character(at: j)
            let isOpen = forward ? pairs[d] != nil : openers[d] != nil
            let isClose = forward ? openers[d] != nil : pairs[d] != nil
            guard isOpen || isClose, mode(j + 1) != .text else { continue }
            if isOpen {
                stack.append(forward ? pairs[d]! : openers[d]!)
            } else {
                guard stack.removeLast() == d else { return nil }
                if stack.isEmpty { return j }
            }
        }
        return nil
    }
}

extension Buffer {
    public func bracketPair(at caret: Int) -> (NSRange, NSRange)? {
        guard isTypst else { return nil }
        return BracketMatch.pair(in: storage.string as NSString, caret: caret, mode: { mode(at: $0) })
    }

    public func bracketDepths() -> [(location: Int, depth: Int)] {
        guard isTypst else { return [] }
        return BracketMatch.depths(in: storage.string as NSString, mode: { mode(at: $0) })
    }
}
