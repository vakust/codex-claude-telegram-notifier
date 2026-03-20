import Foundation

enum APIError: LocalizedError {
    case badURL
    case invalidResponse
    case httpError(Int)
}

final class APIClient {
    static let shared = APIClient()
    private init() {}

    func checkHealth(baseURL: String) async throws -> Bool {
        guard let url = URL(string: "/health", relativeTo: URL(string: baseURL)) else {
            throw APIError.badURL
        }
        let (_, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return (200..<300).contains(http.statusCode)
    }

    func fetchFeed(baseURL: String, token: String, limit: Int = 30) async throws -> FeedResponse {
        guard var components = URLComponents(string: baseURL) else { throw APIError.badURL }
        components.path = "/v1/mobile/feed"
        components.queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
        guard let url = components.url else { throw APIError.badURL }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.httpError(http.statusCode) }
        return try JSONDecoder().decode(FeedResponse.self, from: data)
    }

    func sendCommand(
        baseURL: String,
        token: String,
        target: String,
        action: String,
        customText: String? = nil
    ) async throws -> CommandResponse {
        guard let url = URL(string: "/v1/mobile/commands", relativeTo: URL(string: baseURL)) else {
            throw APIError.badURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var metadata: [String: Any] = [
            "client": "ios-app",
            "ts": ISO8601DateFormatter().string(from: Date())
        ]
        if let customText, !customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata["custom_text"] = customText
        }

        let body: [String: Any] = [
            "target": target,
            "action": action,
            "metadata": metadata
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.httpError(http.statusCode) }
        return try JSONDecoder().decode(CommandResponse.self, from: data)
    }

    func startPair(baseURL: String, pairCode: String) async throws -> AuthSessionResponse {
        guard let url = URL(string: "/v1/mobile/pair/start", relativeTo: URL(string: baseURL)) else {
            throw APIError.badURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["pair_code": pairCode])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.httpError(http.statusCode) }
        return try JSONDecoder().decode(AuthSessionResponse.self, from: data)
    }

    func refreshSession(baseURL: String, refreshToken: String) async throws -> AuthSessionResponse {
        guard let url = URL(string: "/v1/mobile/auth/refresh", relativeTo: URL(string: baseURL)) else {
            throw APIError.badURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.httpError(http.statusCode) }
        return try JSONDecoder().decode(AuthSessionResponse.self, from: data)
    }
}
