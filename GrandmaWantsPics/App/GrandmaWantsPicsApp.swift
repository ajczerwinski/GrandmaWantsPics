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
        }
    }
}
