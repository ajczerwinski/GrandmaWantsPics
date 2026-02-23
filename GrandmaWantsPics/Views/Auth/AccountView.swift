import SwiftUI
import AuthenticationServices

struct AccountView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showSuccess = false
    @State private var currentNonceHash: String?

    private var authService: AuthService { appVM.authService }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if showSuccess {
                        successView
                    } else if authService.isLinked {
                        linkedView
                    } else {
                        linkAccountView
                    }
                }
                .padding()
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Linked Account View

    private var linkedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Account Protected")
                .font(.title2.bold())

            if let email = authService.currentUserEmail {
                Text(email)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if case .authenticated(let provider) = authService.authState {
                HStack(spacing: 6) {
                    Image(systemName: provider == "apple" ? "apple.logo" : "envelope.fill")
                        .font(.caption)
                    Text(provider == "apple" ? "Apple ID" : "Email")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(8)
            }

            Text("If you reinstall the app, sign in to recover your family and photos.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            Button(role: .destructive) {
                appVM.resetAll()
                dismiss()
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .padding(.top, 24)
        }
        .padding(.top, 32)
    }

    // MARK: - Link Account View

    private var linkAccountView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)

                Text("Protect Your Account")
                    .font(.title2.bold())

                Text("Link an email or Apple ID so you can recover your family and photos if you reinstall the app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 16)

            // Email form
            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password (min 6 characters)", text: $password)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)

                SecureField("Confirm Password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task { await linkEmail() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    } else {
                        Text("Link Account")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(isLoading || email.isEmpty || password.isEmpty || confirmPassword.isEmpty)
            }

            dividerWithText("or")

            // Apple Sign In
            SignInWithAppleButton(.continue) { request in
                let nonceHash = authService.prepareAppleSignInNonce()
                currentNonceHash = nonceHash
                request.requestedScopes = [.email]
                request.nonce = nonceHash
            } onCompletion: { result in
                Task { await handleAppleLink(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .cornerRadius(8)

            if let error = errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Account Linked!")
                .font(.title2.bold())

            Text("You can now recover your family and photos if you reinstall the app.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
        .padding(.top, 32)
    }

    // MARK: - Helpers

    private func dividerWithText(_ text: String) -> some View {
        HStack {
            Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
            Text(text).font(.caption).foregroundStyle(.secondary)
            Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
        }
    }

    private func linkEmail() async {
        errorMessage = nil

        guard password == confirmPassword else {
            errorMessage = "Passwords don't match."
            return
        }
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await authService.linkEmail(email: email, password: password)
            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleAppleLink(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        switch result {
        case .success(let authorization):
            do {
                try await authService.linkApple(authorization: authorization)
                showSuccess = true
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.localizedDescription
            }
        }
    }
}
