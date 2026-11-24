/// An action as an ordered tree, written once as MessagePack for its hash and once as JSON for the
/// request body.
///
/// Keys keep the order they are written in, because Hyperliquid hashes the MessagePack bytes as they
/// are: the same fields in another order sign a different action.
enum ActionValue: Equatable, Sendable {
    case map([Entry])
    case array([ActionValue])
    case string(String)
    case unsigned(UInt64)
    case signed(Int64)
    case bool(Bool)
    case null

    struct Entry: Equatable, Sendable {
        let key: String
        let value: ActionValue
    }
}

extension ActionValue: ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral, ExpressibleByStringLiteral,
    ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral, ExpressibleByNilLiteral
{
    init(dictionaryLiteral elements: (String, ActionValue)...) {
        assert(Set(elements.map(\.0)).count == elements.count, "An action map lists a key twice")
        self = .map(elements.map { Entry(key: $0, value: $1) })
    }

    init(arrayLiteral elements: ActionValue...) {
        self = .array(elements)
    }

    init(stringLiteral value: String) {
        self = .string(value)
    }

    init(integerLiteral value: Int64) {
        self = value < 0 ? .signed(value) : .unsigned(UInt64(value))
    }

    init(booleanLiteral value: Bool) {
        self = .bool(value)
    }

    init(nilLiteral: ()) {
        self = .null
    }
}

// MARK: - MessagePack

extension ActionValue {
    /// The value in MessagePack, each integer, string, array and map in its smallest encoding and a
    /// non-negative signed integer as an unsigned one, so equal actions always give equal bytes.
    var messagePack: [UInt8] {
        var bytes = [UInt8]()
        writeMessagePack(into: &bytes)
        return bytes
    }

    private func writeMessagePack(into bytes: inout [UInt8]) {
        switch self {
        case .null:
            bytes.append(0xc0)
        case .bool(let value):
            bytes.append(value ? 0xc3 : 0xc2)
        case .unsigned(let value):
            switch value {
            case 0..<0x80: bytes.append(UInt8(value))
            case 0..<0x100: bytes += [0xcc, UInt8(value)]
            case 0..<0x1_0000: bytes += [0xcd] + UInt16(value).bigEndianBytes
            case 0..<0x1_0000_0000: bytes += [0xce] + UInt32(value).bigEndianBytes
            default: bytes += [0xcf] + value.bigEndianBytes
            }
        case .signed(let value):
            switch value {
            case 0...: ActionValue.unsigned(UInt64(value)).writeMessagePack(into: &bytes)
            case -32..<0: bytes.append(UInt8(bitPattern: Int8(value)))
            case Int64(Int8.min)..<0: bytes += [0xd0, UInt8(bitPattern: Int8(value))]
            case Int64(Int16.min)..<0: bytes += [0xd1] + Int16(value).bigEndianBytes
            case Int64(Int32.min)..<0: bytes += [0xd2] + Int32(value).bigEndianBytes
            default: bytes += [0xd3] + value.bigEndianBytes
            }
        case .string(let value):
            let utf8 = Array(value.utf8)
            switch utf8.count {
            case 0..<32: bytes.append(0xa0 | UInt8(utf8.count))
            case 0..<0x100: bytes += [0xd9, UInt8(utf8.count)]
            case 0..<0x1_0000: bytes += [0xda] + UInt16(utf8.count).bigEndianBytes
            default: bytes += [0xdb] + UInt32(utf8.count).bigEndianBytes
            }
            bytes += utf8
        case .array(let elements):
            switch elements.count {
            case 0..<16: bytes.append(0x90 | UInt8(elements.count))
            case 0..<0x1_0000: bytes += [0xdc] + UInt16(elements.count).bigEndianBytes
            default: bytes += [0xdd] + UInt32(elements.count).bigEndianBytes
            }
            for element in elements { element.writeMessagePack(into: &bytes) }
        case .map(let entries):
            switch entries.count {
            case 0..<16: bytes.append(0x80 | UInt8(entries.count))
            case 0..<0x1_0000: bytes += [0xde] + UInt16(entries.count).bigEndianBytes
            default: bytes += [0xdf] + UInt32(entries.count).bigEndianBytes
            }
            for entry in entries {
                ActionValue.string(entry.key).writeMessagePack(into: &bytes)
                entry.value.writeMessagePack(into: &bytes)
            }
        }
    }
}

// MARK: - JSON

extension ActionValue {
    /// The value as compact JSON, with map keys in their order.
    var json: String {
        var text = ""
        writeJSON(into: &text)
        return text
    }

    private func writeJSON(into text: inout String) {
        switch self {
        case .null: text += "null"
        case .bool(let value): text += value ? "true" : "false"
        case .unsigned(let value): text += String(value)
        case .signed(let value): text += String(value)
        case .string(let value): Self.writeJSONString(value, into: &text)
        case .array(let elements):
            text += "["
            for (index, element) in elements.enumerated() {
                if index > 0 { text += "," }
                element.writeJSON(into: &text)
            }
            text += "]"
        case .map(let entries):
            text += "{"
            for (index, entry) in entries.enumerated() {
                if index > 0 { text += "," }
                Self.writeJSONString(entry.key, into: &text)
                text += ":"
                entry.value.writeJSON(into: &text)
            }
            text += "}"
        }
    }

    private static func writeJSONString(_ value: String, into text: inout String) {
        text += "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": text += "\\\""
            case "\\": text += "\\\\"
            case "\n": text += "\\n"
            case "\r": text += "\\r"
            case "\t": text += "\\t"
            case "\u{0}"..."\u{1F}":
                let digits = String(scalar.value, radix: 16)
                text += "\\u" + String(repeating: "0", count: 4 - digits.count) + digits
            default: text.unicodeScalars.append(scalar)
            }
        }
        text += "\""
    }
}
