import Foundation

enum APIError: LocalizedError {
    case badURL
    case invalidResponse
    case httpError(Int)
}

final class APIClient {
    static let shared = APIClient()
    private init() {}

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

    func sendCommand(baseURL: String, token: String, target: String, action: String) async throws -> CommandResponse {
        guard let url = URL(string: "/v1/mobile/commands", relativeTo: URL(string: baseURL)) else {
            throw APIError.badURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "target": target,
            "action": action,
            "metadata": [
                "client": "ios-app",
                "ts": ISO8601DateFormatter().string(from: Date())
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.httpError(http.statusCode) }
        return try JSONDecoder().decode(CommandResponse.self, from: data)
    }
}
