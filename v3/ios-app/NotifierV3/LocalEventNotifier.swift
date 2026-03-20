import Foundation
import UserNotifications

@MainActor
final class LocalEventNotifier {
    static let shared = LocalEventNotifier()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    func postEventNotification(_ item: FeedEvent, soundEnabled: Bool) async {
        let status = await authorizationStatus()
        guard isAllowed(status: status) else { return }

        let title: String
        switch item.event_type.lowercased() {
        case "done":
            title = "\(item.sourceLabel) done"
        case "command_failed":
            title = "\(item.sourceLabel) failed"
        case "last_text":
            title = "\(item.sourceLabel) final text"
        default:
            title = "\(item.sourceLabel) update"
        }

        let body = (item.payloadText ?? item.payloadSummary ?? "\(item.event_type) at \(item.created_at)")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(body.prefix(280))
        if soundEnabled {
            content.sound = .default
        }
        content.userInfo = [
            "event_id": item.event_id,
            "event_type": item.event_type,
            "source": item.source
        ]

        let request = UNNotificationRequest(
            identifier: stableId(item),
            content: content,
            trigger: nil
        )
        _ = await enqueue(request: request)
    }

    func postTestNotification(soundEnabled: Bool) async {
        let status = await authorizationStatus()
        guard isAllowed(status: status) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Notifier V3 test"
        content.body = "Test notification from iOS app"
        if soundEnabled {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: "local-test-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        _ = await enqueue(request: request)
    }

    private func enqueue(request: UNNotificationRequest) async -> Error? {
        await withCheckedContinuation { continuation in
            center.add(request) { error in
                continuation.resume(returning: error)
            }
        }
    }

    private func stableId(_ item: FeedEvent) -> String {
        if !item.event_id.isEmpty {
            return item.event_id
        }
        return "\(item.created_at)|\(item.source)|\(item.event_type)"
    }

    private func isAllowed(status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }
}
