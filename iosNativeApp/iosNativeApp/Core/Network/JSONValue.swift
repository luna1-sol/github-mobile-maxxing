import Foundation

/// Untyped JSON tree used for GraphQL and REST payloads, mirroring the `JsonObject` helpers
/// (`str`, `int`, `obj`, `arr`) of the Kotlin network layer so the parsers port one to one.
enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self, let value = dict[key], value != .null { return value }
        return nil
    }

    subscript(index: Int) -> JSONValue? {
        if case .array(let items) = self, items.indices.contains(index) { return items[index] }
        return nil
    }

    var string: String? {
        switch self {
        case .string(let s): s
        case .number(let n): n.rounded() == n ? String(Int64(n)) : String(n)
        case .bool(let b): String(b)
        default: nil
        }
    }

    var int: Int? {
        switch self {
        case .number(let n): Int(exactly: n.rounded(.towardZero))
        case .string(let s): Int(s)
        default: nil
        }
    }

    var int64: Int64? {
        switch self {
        case .number(let n): Int64(exactly: n.rounded(.towardZero))
        case .string(let s): Int64(s)
        default: nil
        }
    }

    var bool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    /// Elements of an array; empty for anything else, which keeps parsers free of optional chains.
    var items: [JSONValue] {
        if case .array(let items) = self { return items }
        return []
    }

    var isObject: Bool {
        if case .object = self { return true }
        return false
    }

    func has(_ key: String) -> Bool {
        if case .object(let dict) = self { return dict[key] != nil }
        return false
    }
}

extension JSONValue: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .number(let n): try container.encode(n)
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }

    static func parse(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral, ExpressibleByNilLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    init(nilLiteral: ()) { self = .null }
}
