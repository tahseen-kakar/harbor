import Foundation
import UserNotifications

struct DownloadNotificationPayload: Sendable {
    let identifier: String
    let title: String
    let body: String
}

actor DownloadNotificationService {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func deliver(_ payload: DownloadNotificationPayload) async {
        guard await authorizationGranted() else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: payload.identifier,
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }

    private func authorizationGranted() async -> Bool {
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
}
