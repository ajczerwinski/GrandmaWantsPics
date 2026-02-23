import Foundation
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices
import CryptoKit

enum AuthState: Equatable {
    case signedOut
    case anonymous
    case authenticated(provider: String)
}

@MainActor
final class AuthService: ObservableObject {

    @Published var authState: AuthState = .signedOut
    @Published var currentUserEmail: String?
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private var currentNonce: String?

    nonisolated var currentUserId: String? { Auth.auth().currentUser?.uid }

    nonisolated var isLinked: Bool {
        guard let user = Auth.auth().currentUser else { return false }
        let providers = user.providerData.map(\.providerID)
        return providers.contains("password") || providers.contains("apple.com")
    }

    nonisolated var currentAuthProvider: String {
        guard let user = Auth.auth().currentUser else { return "anonymous" }
        let providers = user.providerData.map(\.providerID)
        if providers.contains("apple.com") { return "apple" }
        if providers.contains("password") { return "email" }
        return "anonymous"
    }

    init() {
        refreshAuthState()
    }

    // MARK: - Auth State

    func refreshAuthState() {
        guard let user = Auth.auth().currentUser else {
            authState = .signedOut
            currentUserEmail = nil
            return
        }
        let providers = user.providerData.map(\.providerID)
        if providers.contains("apple.com") {
            authState = .authenticated(provider: "apple")
            currentUserEmail = user.providerData.first(where: { $0.providerID == "apple.com" })?.email ?? user.email
        } else if providers.contains("password") {
            authState = .authenticated(provider: "email")
            currentUserEmail = user.email
        } else {
            authState = .anonymous
            currentUserEmail = nil
        }
    }

    // MARK: - Anonymous Sign In

    nonisolated func ensureSignedIn() async throws {
        if Auth.auth().currentUser == nil {
            try await Auth.auth().signInAnonymously()
        }
        await MainActor.run { refreshAuthState() }
    }

    // MARK: - Email Linking

    func linkEmail(email: String, password: String) async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthError.notSignedIn
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        do {
            try await user.link(with: credential)
            refreshAuthState()
            try await updateConnectionAuthInfo(email: email, provider: "email")
        } catch let error as NSError {
            throw mapFirebaseError(error)
        }
    }

    // MARK: - Apple Sign In

    func prepareAppleSignInNonce() -> String {
        let nonce = randomNonceString()
        currentNonce = nonce
        return sha256(nonce)
    }

    func linkApple(authorization: ASAuthorization) async throws {
        let credential = try appleCredential(from: authorization)
        guard let user = Auth.auth().currentUser else {
            throw AuthError.notSignedIn
        }
        do {
            try await user.link(with: credential)
            let appleEmail = (authorization.credential as? ASAuthorizationAppleIDCredential)?.email ?? user.email
            refreshAuthState()
            try await updateConnectionAuthInfo(email: appleEmail, provider: "apple")
        } catch let error as NSError {
            throw mapFirebaseError(error)
        }
    }

    // MARK: - Sign In (Recovery)

    func signInWithEmail(email: String, password: String) async throws {
        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
            refreshAuthState()
        } catch let error as NSError {
            throw mapFirebaseError(error)
        }
    }

    func signInWithApple(authorization: ASAuthorization) async throws {
        let credential = try appleCredential(from: authorization)
        do {
            try await Auth.auth().signIn(with: credential)
            refreshAuthState()
        } catch let error as NSError {
            throw mapFirebaseError(error)
        }
    }

    func sendPasswordReset(email: String) async throws {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch let error as NSError {
            throw mapFirebaseError(error)
        }
    }

    // MARK: - Recovery

    func recoverFamilyId() async throws -> String? {
        guard let uid = currentUserId else { return nil }
        let snapshot = try await db.collectionGroup("connections")
            .whereField("userId", isEqualTo: uid)
            .limit(to: 1)
            .getDocuments()
        guard let doc = snapshot.documents.first else { return nil }
        // Path: families/{fid}/connections/{docId} → parent.parent = families/{fid}
        return doc.reference.parent.parent?.documentID
    }

    func recoverConnectionRole() async throws -> String? {
        guard let uid = currentUserId else { return nil }
        let snapshot = try await db.collectionGroup("connections")
            .whereField("userId", isEqualTo: uid)
            .limit(to: 1)
            .getDocuments()
        guard let doc = snapshot.documents.first else { return nil }
        return doc.data()["role"] as? String
    }

    // MARK: - Sign Out

    func signOut() throws {
        try Auth.auth().signOut()
        refreshAuthState()
    }

    // MARK: - Connection Doc Updates

    func updateConnectionAuthInfo(email: String?, provider: String) async throws {
        guard let uid = currentUserId else { return }
        let snapshot = try await db.collectionGroup("connections")
            .whereField("userId", isEqualTo: uid)
            .limit(to: 1)
            .getDocuments()
        guard let doc = snapshot.documents.first else { return }
        var updates: [String: Any] = ["authProvider": provider]
        if let email { updates["email"] = email }
        try await doc.reference.updateData(updates)
    }

    // MARK: - Apple Credential Helper

    private func appleCredential(from authorization: ASAuthorization) throws -> OAuthCredential {
        guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = appleCredential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8),
              let nonce = currentNonce else {
            throw AuthError.invalidAppleCredential
        }
        currentNonce = nil
        return OAuthProvider.appleCredential(withIDToken: tokenString, rawNonce: nonce, fullName: appleCredential.fullName)
    }

    // MARK: - Nonce Utilities

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        precondition(errorCode == errSecSuccess)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Error Mapping

    private func mapFirebaseError(_ error: NSError) -> AuthError {
        let code = AuthErrorCode(rawValue: error.code)
        switch code {
        case .credentialAlreadyInUse, .emailAlreadyInUse:
            return .emailAlreadyInUse
        case .invalidEmail:
            return .invalidEmail
        case .weakPassword:
            return .weakPassword
        case .wrongPassword, .invalidCredential:
            return .wrongPassword
        case .userNotFound:
            return .userNotFound
        case .networkError:
            return .networkError
        default:
            return .unknown(error.localizedDescription)
        }
    }

    // MARK: - Errors

    enum AuthError: LocalizedError {
        case notSignedIn
        case invalidAppleCredential
        case emailAlreadyInUse
        case invalidEmail
        case weakPassword
        case wrongPassword
        case userNotFound
        case networkError
        case unknown(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "Not signed in."
            case .invalidAppleCredential:
                return "Could not process Apple Sign In. Please try again."
            case .emailAlreadyInUse:
                return "This email is already linked to another account."
            case .invalidEmail:
                return "Please enter a valid email address."
            case .weakPassword:
                return "Password must be at least 6 characters."
            case .wrongPassword:
                return "Incorrect email or password."
            case .userNotFound:
                return "No account found with this email."
            case .networkError:
                return "Could not connect. Please check your internet and try again."
            case .unknown(let msg):
                return msg
            }
        }
    }
}
