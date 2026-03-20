import Foundation
import UserNotifications

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var apiURL: String
    @Published var token: String
    @Published var workspaceId: String
    @Published var statusText: String = "Idle"
    @Published var isBusy: Bool = false
    @Published var events: [FeedEvent] = []
    @Published var notificationsEnabled: Bool
    @Published var soundEnabled: Bool
    @Published var notificationsAuthorized: Bool = false

    private var refreshToken: String
    private let defaults: UserDefaults
    private var pollingTask: Task<Void, Never>?
    private var feedPrimed = false
    private var seenEventKeys = Set<String>()
    private var seenEventOrder: [String] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.apiURL = defaults.string(forKey: Self.keyApiURL) ?? "http://127.0.0.1:8787"
        self.token = defaults.string(forKey: Self.keyToken) ?? "dev-mobile-token"
        self.refreshToken = defaults.string(forKey: Self.keyRefreshToken) ?? ""
        self.workspaceId = defaults.string(forKey: Self.keyWorkspaceId) ?? ""
        self.notificationsEnabled = defaults.object(forKey: Self.keyNotificationsEnabled) as? Bool ?? true
        self.soundEnabled = defaults.object(forKey: Self.keySoundEnabled) as? Bool ?? true
    }

    func bootstrap() async {
        await checkHealth()
        _ = await refreshAccessIfPossible()
        await refreshNotificationAuthorization()
        await refresh()
        ensurePolling()
    }

    func checkHealth() async {
        do {
            let healthy = try await APIClient.shared.checkHealth(baseURL: apiURL)
            statusText = healthy ? "Backend is reachable." : "Backend is not reachable."
        } catch {
            statusText = "Health check failed: \(error.localizedDescription)"
        }
    }

    func refresh(silent: Bool = false) async {
        if !silent {
            isBusy = true
            statusText = "Loading feed..."
        }

        do {
            let response = try await runWithAccessRetry {
                try await APIClient.shared.fetchFeed(baseURL: apiURL, token: token, limit: 30)
            }
            let normalized = Array(response.items.reversed())
            await handleEventNotifications(items: normalized)
            events = normalized
            if !silent {
                statusText = "Feed: \(events.count) item(s)"
            }
        } catch {
            if !silent {
                statusText = "Feed error: \(error.localizedDescription)"
            }
        }

        if !silent {
            isBusy = false
        }
    }

    func send(target: String, action: String, customText: String? = nil) async {
        isBusy = true
        statusText = "Sending \(target):\(action)..."
        do {
            let response = try await runWithAccessRetry {
                try await APIClient.shared.sendCommand(
                    baseURL: apiURL,
                    token: token,
                    target: target,
                    action: action,
                    customText: customText
                )
            }
            statusText = "Accepted: \(response.command_id ?? "n/a")"
            await refresh(silent: true)
        } catch {
            statusText = "Command error: \(error.localizedDescription)"
        }
        isBusy = false
    }

    func pairDevice(pairCode: String) async {
        let code = pairCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            statusText = "Pair code is empty."
            return
        }

        statusText = "Pairing device..."
        isBusy = true
        do {
            let session = try await APIClient.shared.startPair(baseURL: apiURL, pairCode: code)
            guard session.ok, let access = session.access_token, !access.isEmpty else {
                statusText = "Pair failed: invalid session."
                isBusy = false
                return
            }
            token = access
            refreshToken = session.refresh_token ?? ""
            workspaceId = session.workspace_id ?? ""
            persistSettings()
            statusText = "Paired with workspace: \(workspaceId)"
            await refresh(silent: true)
        } catch {
            statusText = "Pair failed: \(error.localizedDescription)"
        }
        isBusy = false
    }

    func updateApiURL(_ value: String) {
        apiURL = value
        defaults.set(value, forKey: Self.keyApiURL)
    }

    func updateToken(_ value: String) {
        token = value
        defaults.set(value, forKey: Self.keyToken)
    }

    func updateNotificationsEnabled(_ value: Bool) {
        notificationsEnabled = value
        defaults.set(value, forKey: Self.keyNotificationsEnabled)
    }

    func updateSoundEnabled(_ value: Bool) {
        soundEnabled = value
        defaults.set(value, forKey: Self.keySoundEnabled)
    }

    func refreshNotificationAuthorization() async {
        let status = await LocalEventNotifier.shared.authorizationStatus()
        notificationsAuthorized = isAllowedNotificationStatus(status)
    }

    func requestNotificationPermission() async {
        let granted = await LocalEventNotifier.shared.requestPermission()
        await refreshNotificationAuthorization()
        statusText = granted ? "Notification permission granted." : "Notification permission denied."
    }

    func sendTestNotification() async {
        if !notificationsEnabled {
            statusText = "Notifications are disabled."
            return
        }
        if !notificationsAuthorized {
            statusText = "Grant notification permission first."
            return
        }
        await LocalEventNotifier.shared.postTestNotification(soundEnabled: soundEnabled)
        statusText = soundEnabled ? "Test notification sent (sound ON)." : "Test notification sent (sound OFF)."
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
        defaults.set(notificationsEnabled, forKey: Self.keyNotificationsEnabled)
        defaults.set(soundEnabled, forKey: Self.keySoundEnabled)
    }

    private func ensurePolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                if !self.token.isEmpty {
                    await self.refresh(silent: true)
                }
            }
        }
    }

    private func handleEventNotifications(items: [FeedEvent]) async {
        guard !items.isEmpty else { return }

        if !feedPrimed {
            for item in items {
                rememberEventKey(key(for: item))
            }
            feedPrimed = true
            return
        }

        var fresh: [FeedEvent] = []
        for item in items {
            let eventKey = key(for: item)
            if !seenEventKeys.contains(eventKey) {
                fresh.append(item)
                rememberEventKey(eventKey)
            }
        }

        guard !fresh.isEmpty else { return }
        guard notificationsEnabled else { return }

        if !notificationsAuthorized {
            await refreshNotificationAuthorization()
        }
        guard notificationsAuthorized else { return }

        for item in fresh where shouldNotify(item) {
            await LocalEventNotifier.shared.postEventNotification(item, soundEnabled: soundEnabled)
        }
    }

    private func key(for item: FeedEvent) -> String {
        if !item.event_id.isEmpty {
            return item.event_id
        }
        return "\(item.created_at)|\(item.source)|\(item.event_type)"
    }

    private func rememberEventKey(_ key: String) {
        guard seenEventKeys.insert(key).inserted else { return }
        seenEventOrder.append(key)
        while seenEventOrder.count > 500 {
            let first = seenEventOrder.removeFirst()
            seenEventKeys.remove(first)
        }
    }

    private func shouldNotify(_ item: FeedEvent) -> Bool {
        switch item.event_type.lowercased() {
        case "done", "last_text", "command_failed":
            return true
        default:
            return false
        }
    }

    private func isAllowedNotificationStatus(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    deinit {
        pollingTask?.cancel()
    }

    private static let keyApiURL = "v3.api_url"
    private static let keyToken = "v3.mobile_token"
    private static let keyRefreshToken = "v3.refresh_token"
    private static let keyWorkspaceId = "v3.workspace_id"
    private static let keyNotificationsEnabled = "v3.notifications_enabled"
    private static let keySoundEnabled = "v3.sound_enabled"
}
