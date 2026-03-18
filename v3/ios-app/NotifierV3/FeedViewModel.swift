import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var apiURL: String = "http://127.0.0.1:8787"
    @Published var token: String = "dev-mobile-token"
    @Published var statusText: String = "Idle"
    @Published var events: [FeedEvent] = []

    func refresh() async {
        statusText = "Loading feed..."
        do {
            let response = try await APIClient.shared.fetchFeed(baseURL: apiURL, token: token, limit: 30)
            events = response.items.reversed()
            statusText = "Feed: \(events.count) item(s)"
        } catch {
            statusText = "Feed error: \(error.localizedDescription)"
        }
    }

    func send(target: String, action: String) async {
        statusText = "Sending \(target):\(action)..."
        do {
            let response = try await APIClient.shared.sendCommand(
                baseURL: apiURL,
                token: token,
                target: target,
                action: action
            )
            statusText = "Accepted: \(response.command_id ?? "n/a")"
            await refresh()
        } catch {
            statusText = "Command error: \(error.localizedDescription)"
        }
    }
}
