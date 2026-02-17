import UIKit
import UserNotifications
import FirebaseMessaging

@MainActor
final class NotificationService: NSObject, ObservableObject {

    static let shared = NotificationService()

    @Published var fcmToken: String?

    private override init() {
        super.init()
    }

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            return granted
        } catch {
            print("Notification permission error: \(error)")
            return false
        }
    }

    // MARK: - FCM Setup

    func configureFCM() {
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Token Storage

    func saveFCMToken(store: FamilyStore) async {
        do {
            // Actively fetch token — the delegate callback may not have fired yet
            let token = try await Messaging.messaging().token()
            fcmToken = token
            try await store.saveFCMToken(token)
        } catch {
            print("Failed to save FCM token: \(error)")
        }
    }
}

// MARK: - MessagingDelegate

extension NotificationService: MessagingDelegate {

    nonisolated func messaging(
        _ messaging: Messaging,
        didReceiveRegistrationToken fcmToken: String?
    ) {
        guard let fcmToken else { return }
        print("FCM token: \(fcmToken)")
        Task { @MainActor in
            self.fcmToken = fcmToken
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .badge, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Handle notification tap — the app opens and existing routing handles navigation
    }
}
