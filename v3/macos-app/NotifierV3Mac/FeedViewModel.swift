import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var apiURL = "http://127.0.0.1:8787"
    @Published var token = "dev-mobile-token"
    @Published var statusText = "Ready"
    @Published var feedItems: [FeedEvent] = []

    func refreshFeed() async {
        statusText = "Loading feed..."
        do {
            let response = try await APIClient.shared.fetchFeed(baseURL: apiURL, token: token, limit: 30)
            feedItems = response.items
            statusText = "Feed loaded: \(feedItems.count)"
        } catch {
            statusText = "Feed error: \(error.localizedDescription)"
        }
    }

    func sendCommand(target: String, action: String) async {
        statusText = "Sending \(target):\(action)..."
        do {
            let response = try await APIClient.shared.sendCommand(
                baseURL: apiURL,
                token: token,
                target: target,
                action: action
            )
            statusText = "Accepted: \(response.command_id)"
            await refreshFeed()
        } catch {
            statusText = "Command error: \(error.localizedDescription)"
        }
    }
}
