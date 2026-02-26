import SwiftUI

struct PairingView: View {
    @EnvironmentObject var appVM: AppViewModel
    let role: AppRole

    @State private var enteredCode = ""
    @State private var generatedCode: String?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var isCreating = false
    @State private var showShareSheet = false
    @State private var showManualCode = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            if role == .adult {
                adultPairingView
            } else {
                grandmaPairingView
            }

            Spacer()
        }
        .padding(32)
    }

    // MARK: - Adult: Share Invite Link

    @ViewBuilder
    private var adultPairingView: some View {
        VStack(spacing: 20) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 50))
                .foregroundStyle(.blue)

            Text("Connect Grandma's App")
                .font(.title.bold())

            if let code = generatedCode ?? appVM.pairingCode {
                Text("Text Grandma the invite link.\nShe just needs to tap it once to connect.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Button {
                    showShareSheet = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Send Invite to Grandma")
                    }
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.gradient)
                    .cornerRadius(16)
                }
                .sheet(isPresented: $showShareSheet) {
                    ActivityView(activityItems: [appVM.shareMessage])
                }

                DisclosureGroup("Having trouble?", isExpanded: $showManualCode) {
                    VStack(spacing: 8) {
                        Text("Share this code manually:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(code)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .padding(8)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                            .textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = code
                        } label: {
                            Label("Copy Code", systemImage: "doc.on.doc")
                                .font(.subheadline)
                        }
                    }
                    .padding(.top, 8)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal)

                Button {
                    appVM.confirmPairing()
                } label: {
                    Text("Open My Inbox")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.gradient)
                        .cornerRadius(16)
                }
            } else {
                Text("You'll text Grandma a link — she taps it once and you're connected.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 14) {
                    stepRow(number: "1", text: "We create a private invite link", color: .blue)
                    stepRow(number: "2", text: "You send it to Grandma by text or email", color: .blue)
                    stepRow(number: "3", text: "She taps the link — you're connected!", color: .blue)
                }
                .padding()
                .background(Color.blue.opacity(0.07))
                .cornerRadius(14)

                Button {
                    Task {
                        isCreating = true
                        await appVM.createFamily()
                        generatedCode = appVM.pairingCode
                        isCreating = false
                        if generatedCode != nil {
                            showShareSheet = true
                        }
                    }
                } label: {
                    HStack {
                        if isCreating {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "link.badge.plus")
                        }
                        Text(isCreating ? "Creating invite..." : "Create & Send Invite")
                    }
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(isCreating ? AnyShapeStyle(Color.gray) : AnyShapeStyle(Color.blue.gradient))
                    .cornerRadius(16)
                }
                .disabled(isCreating)
            }
        }
    }

    // MARK: - Grandma: Wait for Invite Link

    @ViewBuilder
    private var grandmaPairingView: some View {
        VStack(spacing: 20) {
            Image(systemName: "envelope.open.fill")
                .font(.system(size: 50))
                .foregroundStyle(.pink)

            Text("Connecting to Your Family")
                .font(.title.bold())

            Text("Ask your family to send you an invite.\nYou'll get a link in a text message.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                stepRow(number: "1", text: "Your family opens GrandmaWantsPics and taps \"Create & Send Invite\"", color: .pink)
                stepRow(number: "2", text: "They send you a link by text message", color: .pink)
                stepRow(number: "3", text: "You tap the link — the app connects automatically!", color: .pink)
            }
            .padding()
            .background(Color.pink.opacity(0.07))
            .cornerRadius(14)

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.subheadline)
            }

            DisclosureGroup("I have a code to enter", isExpanded: $showManualCode) {
                VStack(spacing: 12) {
                    TextField("Paste code here", text: $enteredCode)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.default)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .frame(maxWidth: 320)

                    Button {
                        Task {
                            isLoading = true
                            errorMessage = nil
                            let ok = await appVM.joinFamily(code: enteredCode, asRole: role.rawValue)
                            if !ok {
                                errorMessage = "Invalid or expired code. Try again."
                            }
                            isLoading = false
                        }
                    } label: {
                        HStack {
                            if isLoading { ProgressView().tint(.white) }
                            Text("Connect")
                        }
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(enteredCode.isEmpty ? Color.gray : Color.pink)
                        .cornerRadius(16)
                    }
                    .disabled(enteredCode.isEmpty || isLoading)
                }
                .padding(.top, 8)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal)
        }
    }

    // MARK: - Helpers

    private func stepRow(number: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(color)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }
}
