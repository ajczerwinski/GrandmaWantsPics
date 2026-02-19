import SwiftUI

struct PairingView: View {
    @EnvironmentObject var appVM: AppViewModel
    let role: AppRole

    @State private var enteredCode = ""
    @State private var generatedCode: String?
    @State private var errorMessage: String?
    @State private var isLoading = false
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

            Text("Set Up for Grandma")
                .font(.title.bold())

            if let code = generatedCode ?? appVM.pairingCode {
                VStack(spacing: 16) {
                    Text("Invite link ready!")
                        .font(.title3)

                    Button {
                        showShareSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Send Invite")
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

                    // Collapsed fallback with manual code
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
                }

                Button {
                    appVM.confirmPairing()
                } label: {
                    Text("Continue to Inbox")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.gradient)
                        .cornerRadius(16)
                }
            } else {
                Button {
                    Task {
                        await appVM.createFamily()
                        generatedCode = appVM.pairingCode
                    }
                } label: {
                    HStack {
                        Image(systemName: "link.badge.plus")
                        Text("Create Invite Link")
                    }
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.gradient)
                    .cornerRadius(16)
                }
            }
        }
    }

    // MARK: - Grandma: Enter Code

    @ViewBuilder
    private var grandmaPairingView: some View {
        VStack(spacing: 20) {
            Image(systemName: "link")
                .font(.system(size: 50))
                .foregroundStyle(.pink)

            Text("Enter Your Code")
                .font(.title.bold())

            Text("Ask your family for the\ninvite link or pairing code.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            TextField("Paste code here", text: $enteredCode)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.default)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .frame(maxWidth: 320)

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            }

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
    }
}
