import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @EnvironmentObject var appVM: AppViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showResetConfirmation = false
    @State private var currentNonceHash: String?

    private var authService: AuthService { appVM.authService }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)

                        Text("Welcome Back")
                            .font(.title.bold())

                        Text("Sign in to recover your family and photos.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 32)

                    // Email form
                    VStack(spacing: 12) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .textFieldStyle(.roundedBorder)

                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            Task { await signInWithEmail() }
                        } label: {
                            if isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            } else {
                                Text("Sign In")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(isLoading || email.isEmpty || password.isEmpty)

                        Button("Forgot password?") {
                            Task { await sendReset() }
                        }
                        .font(.callout)
                        .foregroundStyle(.blue)
                    }

                    dividerWithText("or")

                    // Apple Sign In
                    SignInWithAppleButton(.signIn) { request in
                        let nonceHash = authService.prepareAppleSignInNonce()
                        currentNonceHash = nonceHash
                        request.requestedScopes = [.email]
                        request.nonce = nonceHash
                    } onCompletion: { result in
                        Task { await handleAppleSignIn(result) }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .cornerRadius(8)

                    if let error = errorMessage ?? appVM.recoveryError {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    if showResetConfirmation {
                        Text("Password reset email sent. Check your inbox.")
                            .font(.callout)
                            .foregroundStyle(.green)
                            .multilineTextAlignment(.center)
                    }

                    Spacer(minLength: 32)

                    Button("Back") {
                        appVM.showSignIn = false
                    }
                    .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Helpers

    private func dividerWithText(_ text: String) -> some View {
        HStack {
            Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
            Text(text).font(.caption).foregroundStyle(.secondary)
            Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
        }
    }

    private func signInWithEmail() async {
        errorMessage = nil
        showResetConfirmation = false
        isLoading = true
        defer { isLoading = false }

        do {
            try await authService.signInWithEmail(email: email, password: password)
            await appVM.recoverAccount()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        switch result {
        case .success(let authorization):
            do {
                try await authService.signInWithApple(authorization: authorization)
                await appVM.recoverAccount()
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func sendReset() async {
        errorMessage = nil
        showResetConfirmation = false

        guard !email.isEmpty else {
            errorMessage = "Enter your email address first."
            return
        }

        do {
            try await authService.sendPasswordReset(email: email)
            showResetConfirmation = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
