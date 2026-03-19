import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var apiURL: String
    @Published var token: String
    @Published var workspaceId: String
    @Published var statusText: String = "Idle"
    @Published var events: [FeedEvent] = []

    private var refreshToken: String
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.apiURL = defaults.string(forKey: Self.keyApiURL) ?? "http://127.0.0.1:8787"
        self.token = defaults.string(forKey: Self.keyToken) ?? "dev-mobile-token"
        self.refreshToken = defaults.string(forKey: Self.keyRefreshToken) ?? ""
        self.workspaceId = defaults.string(forKey: Self.keyWorkspaceId) ?? ""
    }

    func bootstrap() async {
        do {
            let healthy = try await APIClient.shared.checkHealth(baseURL: apiURL)
            statusText = healthy ? "Backend is reachable." : "Backend is not reachable."
        } catch {
            statusText = "Health check failed: \(error.localizedDescription)"
        }
        _ = await refreshAccessIfPossible()
        await refresh()
    }

    func refresh() async {
        statusText = "Loading feed..."
        do {
            let response = try await runWithAccessRetry {
                try await APIClient.shared.fetchFeed(baseURL: apiURL, token: token, limit: 30)
            }
            events = response.items.reversed()
            statusText = "Feed: \(events.count) item(s)"
        } catch {
            statusText = "Feed error: \(error.localizedDescription)"
        }
    }

    func send(target: String, action: String) async {
        statusText = "Sending \(target):\(action)..."
        do {
            let response = try await runWithAccessRetry {
                try await APIClient.shared.sendCommand(
                    baseURL: apiURL,
                    token: token,
                    target: target,
                    action: action
                )
            }
            statusText = "Accepted: \(response.command_id ?? "n/a")"
            await refresh()
        } catch {
            statusText = "Command error: \(error.localizedDescription)"
        }
    }

    func pairDevice(pairCode: String) async {
        let code = pairCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            statusText = "Pair code is empty."
            return
        }

        statusText = "Pairing device..."
        do {
            let session = try await APIClient.shared.startPair(baseURL: apiURL, pairCode: code)
            guard session.ok, let access = session.access_token, !access.isEmpty else {
                statusText = "Pair failed: invalid session."
                return
            }
            token = access
            refreshToken = session.refresh_token ?? ""
            workspaceId = session.workspace_id ?? ""
            persistSettings()
            statusText = "Paired with workspace: \(workspaceId)"
            await refresh()
        } catch {
            statusText = "Pair failed: \(error.localizedDescription)"
        }
    }

    func updateApiURL(_ value: String) {
        apiURL = value
        defaults.set(value, forKey: Self.keyApiURL)
    }

    func updateToken(_ value: String) {
        token = value
        defaults.set(value, forKey: Self.keyToken)
    }

    private func runWithAccessRetry<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch APIError.httpError(let code) where code == 401 {
            let refreshed = await refreshAccessIfPossible()
            guard refreshed else { throw APIError.httpError(401) }
            return try await operation()
        } catch {
            throw error
        }
    }

    private func refreshAccessIfPossible() async -> Bool {
        guard !refreshToken.isEmpty else { return false }
        do {
            let session = try await APIClient.shared.refreshSession(baseURL: apiURL, refreshToken: refreshToken)
            guard session.ok, let access = session.access_token, !access.isEmpty else { return false }
            token = access
            refreshToken = session.refresh_token ?? refreshToken
            workspaceId = session.workspace_id ?? workspaceId
            persistSettings()
            return true
        } catch {
            return false
        }
    }

    private func persistSettings() {
        defaults.set(apiURL, forKey: Self.keyApiURL)
        defaults.set(token, forKey: Self.keyToken)
        defaults.set(refreshToken, forKey: Self.keyRefreshToken)
        defaults.set(workspaceId, forKey: Self.keyWorkspaceId)
    }

    private static let keyApiURL = "v3.api_url"
    private static let keyToken = "v3.mobile_token"
    private static let keyRefreshToken = "v3.refresh_token"
    private static let keyWorkspaceId = "v3.workspace_id"
}
