import SwiftUI
import FirebaseCore
import FirebaseMessaging

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
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
                    // Widget deep links: grandmawantspics://inbox, grandmawantspics://home, etc.
                    // The app's existing ContentView routing handles showing the correct
                    // screen based on role and pairing state, so just opening the app suffices.
                    guard url.scheme == AppGroupConstants.deepLinkScheme else { return }
                }
        }
    }
}
