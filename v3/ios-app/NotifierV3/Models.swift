import Foundation

struct FeedEvent: Codable, Identifiable {
    let event_id: String
    let event_type: String
    let source: String
    let session_key: String?
    let created_at: String
    let payload: [String: String]?

    var id: String { event_id }
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
