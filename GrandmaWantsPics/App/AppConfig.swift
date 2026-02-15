import Foundation

enum AppConfig {
    /// Set to `true` to use Firebase backend (Phase 1).
    /// When `false`, the app runs entirely in local demo mode (Phase 0).
    /// Auto-detects: if GoogleService-Info.plist is missing, falls back to local.
    static var useFirebase: Bool {
        guard _useFirebaseOverride == nil else { return _useFirebaseOverride! }
        return Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
    }

    /// Override for testing. Set before app launches if needed.
    static var _useFirebaseOverride: Bool?
}
