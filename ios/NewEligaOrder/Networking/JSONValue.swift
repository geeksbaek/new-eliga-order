import Foundation

enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "지원하지 않는 JSON 값입니다") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var objectValue: [String: JSONValue] {
        if case .object(let value) = self { return value }
        return [:]
    }

    var arrayValue: [JSONValue] {
        if case .array(let value) = self { return value }
        return []
    }

    var stringValue: String {
        switch self {
        case .string(let value): return value
        case .number(let value): return value.rounded() == value ? String(Int(value)) : String(value)
        case .bool(let value): return String(value)
        default: return ""
        }
    }

    var intValue: Int? {
        switch self {
        case .number(let value): return Int(value)
        case .string(let value): return Int(value)
        default: return nil
        }
    }

    var boolValue: Bool {
        switch self {
        case .bool(let value): return value
        case .number(let value): return value != 0
        case .string(let value): return ["y", "yes", "true", "1"].contains(value.lowercased())
        default: return false
        }
    }

    subscript(_ key: String) -> JSONValue {
        objectValue[key] ?? .null
    }

    var content: JSONValue {
        objectValue["content"] ?? self
    }
}

extension JSONValue {
    static func int(_ value: Int) -> JSONValue { .number(Double(value)) }

    static func localize(_ value: JSONValue) -> String {
        switch value {
        case .string, .number, .bool:
            return value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        case .object(let object):
            let korean = localize(object["ko"] ?? .null)
            if !korean.isEmpty { return korean }
            return localize(object["en"] ?? .null)
        default:
            return ""
        }
    }
}
