import Foundation

enum JSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .number(Double(intValue))
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .number(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let objectValue = try? container.decode([String: JSONValue].self) {
            self = .object(objectValue)
        } else if let arrayValue = try? container.decode([JSONValue].self) {
            self = .array(arrayValue)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
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

    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .object, .array, .null:
            return nil
        }
    }
}

struct FeedEvent: Codable, Identifiable {
    let event_id: String
    let event_type: String
    let source: String
    let session_key: String?
    let created_at: String
    let payload: [String: JSONValue]?

    var id: String { event_id }

    var sourceLabel: String {
        switch source.lowercased() {
        case "codex":
            return "Codex"
        case "cc":
            return "Cloud Code"
        default:
            return source
        }
    }

    var payloadText: String? {
        guard let payload else { return nil }
        let preferredKeys = ["text", "message", "caption", "summary", "status", "note", "body"]
        for key in preferredKeys {
            if let value = payload[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    var imageReference: String? {
        guard let payload else { return nil }
        let preferredKeys = [
            "image_url", "screenshot_url", "photo_url", "url", "image", "screenshot", "photo", "file"
        ]
        for key in preferredKeys {
            if let value = payload[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        for (key, value) in payload {
            let lower = key.lowercased()
            let looksLikeImageKey =
                lower.contains("url") ||
                lower.contains("image") ||
                lower.contains("shot") ||
                lower.contains("photo")
            if looksLikeImageKey,
               let str = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !str.isEmpty {
                return str
            }
        }
        return nil
    }

    var payloadSummary: String? {
        guard let payload, !payload.isEmpty else { return nil }
        let pairs = payload
            .prefix(3)
            .map { key, value in
                if let stringValue = value.stringValue {
                    return "\(key)=\(stringValue)"
                }
                return "\(key)=..."
            }
        return pairs.joined(separator: " | ")
    }
}

struct FeedResponse: Codable {
    let ok: Bool
    let items: [FeedEvent]
    let next_cursor: String?
}

struct CommandResponse: Codable {
    let ok: Bool
    let command_id: String?
    let status: String?
}

struct AuthSessionResponse: Codable {
    let ok: Bool
    let workspace_id: String?
    let access_token: String?
    let refresh_token: String?
    let access_expires_at: String?
    let refresh_expires_at: String?
}
