import Foundation

/// Arbitrary JSON value for `params` dictionaries and free-form `prefs`.
enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let single = try? decoder.singleValueContainer()
        if let container = single, container.decodeNil() {
            self = .null
            return
        }
        if let keyed = try? decoder.container(keyedBy: DynamicKey.self) {
            var object: [String: JSONValue] = [:]
            for key in keyed.allKeys {
                object[key.stringValue] = try keyed.decode(JSONValue.self, forKey: key)
            }
            self = .object(object)
            return
        }
        if var unkeyed = try? decoder.unkeyedContainer() {
            var array: [JSONValue] = []
            while !unkeyed.isAtEnd {
                array.append(try unkeyed.decode(JSONValue.self))
            }
            self = .array(array)
            return
        }
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) { self = .bool(b); return }
        if let n = try? container.decode(Double.self) { self = .number(n); return }
        if let s = try? container.decode(String.self) { self = .string(s); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let v): var c = encoder.singleValueContainer(); try c.encode(v)
        case .number(let v): var c = encoder.singleValueContainer(); try c.encode(v)
        case .bool(let v): var c = encoder.singleValueContainer(); try c.encode(v)
        case .null: var c = encoder.singleValueContainer(); try c.encodeNil()
        case .array(let v): var c = encoder.unkeyedContainer(); try c.encode(contentsOf: v)
        case .object(let v): var c = encoder.container(keyedBy: DynamicKey.self)
            for (key, value) in v { try c.encode(value, forKey: DynamicKey(stringValue: key)) }
        }
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

/// `{"data": ...}` success envelope.
struct Envelope<T: Decodable>: Decodable {
    let data: T
}
