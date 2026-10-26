import Foundation

/// Image-provided identification, stored as the `image` block of `/.uuid`.
///
/// The block is owned by the image: an image build can ship a `/.uuid` that contains only
/// `schemaVersion` and `image`. SwiftFlash never changes it; after flashing it copies the block
/// unchanged (including unknown fields) into the `.uuid` it writes. See `docs/uuid-file.md`.
public struct ImageIdentity: Codable, Equatable, Sendable {
    public var id: String?
    public var name: String?
    public var version: String?
    public var build: String?
    /// Fields not known to SwiftFlash, preserved as-is.
    public var additionalFields: [String: JSONValue]

    public init(
        id: String? = nil,
        name: String? = nil,
        version: String? = nil,
        build: String? = nil,
        additionalFields: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.build = build
        self.additionalFields = additionalFields
    }

    /// Short label such as `Redox OS 0.9.1`, or nil if the block carries no name, id or version.
    public var displayLabel: String? {
        let parts = [name ?? id, version].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private static let knownKeys: Set<String> = ["id", "name", "version", "build"]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        id = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("id"))
        name = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("name"))
        version = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("version"))
        build = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("build"))
        var additionalFields: [String: JSONValue] = [:]
        for key in container.allKeys where !Self.knownKeys.contains(key.stringValue) {
            additionalFields[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        self.additionalFields = additionalFields
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        for (key, value) in additionalFields where !Self.knownKeys.contains(key) {
            try container.encode(value, forKey: DynamicCodingKey(key))
        }
        try container.encodeIfPresent(id, forKey: DynamicCodingKey("id"))
        try container.encodeIfPresent(name, forKey: DynamicCodingKey("name"))
        try container.encodeIfPresent(version, forKey: DynamicCodingKey("version"))
        try container.encodeIfPresent(build, forKey: DynamicCodingKey("build"))
    }
}

/// Minimal JSON value used to round-trip unknown fields.
public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

/// What SwiftFlash reads from an image-provided `/.uuid`: only the `image` block matters.
struct ImageUUIDFile: Decodable {
    var image: ImageIdentity?
}

struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        nil
    }
}
