import Foundation

/// A JSON value of a JSON-RPC message; Sendable, unlike what JSONSerialization returns.
public enum JSONValue: Sendable, Equatable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
                       ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    case null, bool(Bool), int(Int), double(Double), string(String), array([JSONValue]), object([String: JSONValue])

    public init(stringLiteral v: String) { self = .string(v) }
    public init(integerLiteral v: Int) { self = .int(v) }
    public init(booleanLiteral v: Bool) { self = .bool(v) }
    public init(arrayLiteral v: JSONValue...) { self = .array(v) }
    public init(dictionaryLiteral v: (String, JSONValue)...) { self = .object(Dictionary(v) { $1 }) }
    public init(nilLiteral: ()) { self = .null }

    public subscript(key: String) -> JSONValue? { if case .object(let o) = self { o[key] } else { nil } }
    public var string: String? { if case .string(let s) = self { s } else { nil } }
    public var int: Int? { switch self { case .int(let i): i; case .double(let d): Int(exactly: d); default: nil } }
    public var bool: Bool? { if case .bool(let b) = self { b } else { nil } }
    public var array: [JSONValue]? { if case .array(let a) = self { a } else { nil } }

    public init(any: Any) {
        switch any {
        // JSONSerialization gives NSNumber for both; only the type id tells a boolean from 0 and 1.
        case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID(): self = .bool(n.boolValue)
        case let n as NSNumber: self = CFNumberIsFloatType(n) ? .double(n.doubleValue) : .int(n.intValue)
        case let s as String: self = .string(s)
        case let a as [Any]: self = .array(a.map(JSONValue.init(any:)))
        case let o as [String: Any]: self = .object(o.mapValues(JSONValue.init(any:)))
        default: self = .null
        }
    }

    public var any: Any {
        switch self {
        case .null: NSNull()
        case .bool(let b): b
        case .int(let i): i
        case .double(let d): d
        case .string(let s): s
        case .array(let a): a.map(\.any)
        case .object(let o): o.mapValues(\.any)
        }
    }

    public init(json: Data) throws { self.init(any: try JSONSerialization.jsonObject(with: json, options: .fragmentsAllowed)) }
    /// One line: JSONSerialization escapes every newline inside strings.
    public var json: Data { (try? JSONSerialization.data(withJSONObject: any, options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes])) ?? Data("null".utf8) }
}

/// A JSON-RPC error, sent or received.
public struct JSONRPCError: Error, Equatable, Sendable {
    public var code: Int
    public var message: String
    public init(_ code: Int, _ message: String) { self.code = code; self.message = message }

    public static let methodNotFound = -32601, invalidParams = -32602, internalError = -32603
}

/// JSON-RPC over a byte stream, one message per line.
public enum JSONRPCLines {
    /// Reads `fd` until its end and hands over each line without its newline. Only "\n" ends a line: JSON writers may
    /// leave U+2028 and other line breaks raw inside strings.
    public static func read(_ fd: Int32, line: (Data) -> Void) {
        var pending = Data()
        var buf = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = Darwin.read(fd, &buf, buf.count)
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { return }
            pending.append(contentsOf: buf[0..<n])
            while let nl = pending.firstIndex(of: 0x0A) {
                line(Data(pending[pending.startIndex..<nl]))
                pending.removeSubrange(pending.startIndex...nl)
            }
        }
    }
}
