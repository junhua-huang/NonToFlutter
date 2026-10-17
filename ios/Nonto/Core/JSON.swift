import Foundation

/// The server mixes numeric/string IDs and bare/enveloped lists. Keep this
/// compatibility at the wire boundary rather than silently losing fields.
indirect enum JSON: Codable, Equatable, Sendable {
    case object([String: JSON]), array([JSON]), string(String), number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSON].self) { self = .object(v) }
        else { self = .array(try c.decode([JSON].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    subscript(_ key: String) -> JSON {
        get { object[key] ?? .null }
        set { var o = object; o[key] = newValue; self = .object(o) }
    }
    var object: [String: JSON] { if case .object(let v) = self { return v }; return [:] }
    var array: [JSON] { if case .array(let v) = self { return v }; return [] }
    var string: String {
        switch self {
        case .string(let v): return v
        case .number(let v): return v.rounded() == v ? String(format: "%.0f", v) : String(v)
        default: return ""
        }
    }
    var int: Int { if case .number(let v) = self, v.isFinite, abs(v) < Double(Int.max) { return Int(v) }; return Int(string) ?? 0 }
    var bool: Bool { self == .bool(true) || self == .number(1) || string == "true" || string == "1" }
    var isNull: Bool { self == .null }
    func or(_ fallback: JSON) -> JSON { isNull ? fallback : self }
    func list(_ keys: String...) -> [JSON] {
        if case .array = self { return array }
        for key in keys { if case .array = self[key] { return self[key].array } }
        return []
    }
    func merging(_ patch: JSON) -> JSON { .object(object.merging(patch.object) { _, new in new }) }
    static func id(_ n: Int) -> JSON { .number(Double(n)) }
    static func text(_ s: String) -> JSON { .string(s) }
    static func decode(_ data: Data) throws -> JSON { try JSONDecoder().decode(JSON.self, from: data) }
    func encoded() throws -> Data { try JSONEncoder().encode(self) }
}

enum ServerDate {
    static func parse(_ value: JSON) -> Date? {
        let text = value.string
        guard !text.isEmpty else { return nil }
        if let n = Double(text) { return Date(timeIntervalSince1970: n > 1_000_000_000_000 ? n / 1000 : n) }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: text) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: text) { return d }
        // Legacy backend dates without an offset are Beijing time, not device time.
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "Asia/Shanghai"); f.dateFormat = format
            if let d = f.date(from: text) { return d }
        }
        return nil
    }
}
