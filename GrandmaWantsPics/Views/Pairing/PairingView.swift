import SwiftUI

struct PairingView: View {
    @EnvironmentObject var appVM: AppViewModel
    let role: AppRole

    @State private var enteredCode = ""
    @State private var generatedCode: String?
    @State private var errorMessage: String?
    @State private var isLoading = false

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

    // MARK: - Adult: Generate Code

    @ViewBuilder
    private var adultPairingView: some View {
        VStack(spacing: 20) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 50))
                .foregroundStyle(.blue)

            Text("Set Up for Grandma")
                .font(.title.bold())

            if let code = generatedCode ?? appVM.pairingCode {
                VStack(spacing: 12) {
                    Text("Give this code to Grandma:")
                        .font(.title3)
                    Text(code)
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(16)
                    Text("She'll enter it on her device.")
                        .foregroundStyle(.secondary)
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
                    Text("Generate Pairing Code")
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

            Text("Ask your family for the\npairing code.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            TextField("Code", text: $enteredCode)
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .frame(maxWidth: 200)

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    isLoading = true
                    errorMessage = nil
                    let ok = await appVM.joinFamily(code: enteredCode)
                    if !ok {
                        errorMessage = "Invalid code. Try again."
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
