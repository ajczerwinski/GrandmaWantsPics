import UIKit
import UserNotifications
import FirebaseMessaging

@MainActor
final class NotificationService: NSObject, ObservableObject {

    static let shared = NotificationService()

    @Published var fcmToken: String?
    var onNotificationTap: ((String) -> Void)?

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
            #if DEBUG
            print("Notification permission error: \(error)")
            #endif
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
            #if DEBUG
            print("Failed to save FCM token: \(error)")
            #endif
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
        #if DEBUG
        print("FCM token: \(fcmToken)")
        #endif
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
        let type = response.notification.request.content.userInfo["type"] as? String ?? ""
        guard !type.isEmpty else { return }
        await MainActor.run { [self] in
            onNotificationTap?(type)
        }
    }
}
