import SwiftUI
import FirebaseCore

@main
struct GrandmaWantsPicsApp: App {
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
