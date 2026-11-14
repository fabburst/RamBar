import Foundation
import UserNotifications

@MainActor
public final class NotificationManager {
    public static let shared = NotificationManager()

    private var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private init() {}

    public func requestAuthorizationIfNeeded() {
        guard isBundledApp else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func notifyAutoClose(appName: String, freedText: String) {
        guard isBundledApp else { return }
        let content = UNMutableNotificationContent()
        content.title = L10n.string("notif.autoclose.title")
        content.body = "\(appName) (\(freedText))"
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "autoclose-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    public func notifyCriticalPressure() {
        guard isBundledApp else { return }
        let content = UNMutableNotificationContent()
        content.title = L10n.string("notif.critical.title")
        content.body = L10n.string("notif.critical.body")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "critical-pressure-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
