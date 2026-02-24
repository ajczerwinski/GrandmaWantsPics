import SwiftUI
import FirebaseCore
import FirebaseMessaging

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Delegate must be set before app finishes launching (Apple requirement)
        UNUserNotificationCenter.current().delegate = NotificationService.shared
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }
}

@main
struct GrandmaWantsPicsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var appVM: AppViewModel

    init() {
        // Configure Firebase if GoogleService-Info.plist is present
        if AppConfig.useFirebase {
            FirebaseApp.configure()
        }
        _appVM = StateObject(wrappedValue: AppViewModel())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appVM)
                .onOpenURL { url in
                    appVM.handleDeepLink(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL {
                        appVM.handleDeepLink(url)
                    }
                }
        }
    }
}
