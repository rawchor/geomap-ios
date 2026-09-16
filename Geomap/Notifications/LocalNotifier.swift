import UserNotifications

/// Local (on-device) notifications only — there's no APNs/push
/// infrastructure on the backend yet, so this can only alert the user
/// while the app process is actually running (foreground or briefly
/// backgrounded), not when fully closed. That's a real limitation, not
/// an oversight: true background push would need backend work (device
/// token registration, APNs integration) that doesn't exist yet.
@MainActor
final class LocalNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LocalNotifier()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func postNewMessageNotification(friendDisplayName: String, preview: String) {
        let content = UNMutableNotificationContent()
        content.title = friendDisplayName
        content.body = preview
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Without this, a notification posted while the app is in the
    /// foreground is silently swallowed instead of showing a banner.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
