import SwiftUI

struct GrandmaHomeView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var showConfirmation = false
    @State private var showGallery = false
    @State private var lastRequestTime: Date?
    @State private var hasPromptedNotifications = false
    @State private var isSending = false
    @State private var showDuplicateAlert = false
    @State private var showSwitchRoleAlert = false

    private var fulfilledPhotosExist: Bool {
        appVM.store.requests.contains(where: { $0.status == .fulfilled })
    }

    private var hasPendingRequest: Bool {
        appVM.store.requests.contains(where: { $0.status == .pending })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Button {
                    if hasPendingRequest {
                        showDuplicateAlert = true
                    } else {
                        Task { await sendRequest() }
                    }
                } label: {
                    VStack(spacing: 16) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 60))
                        Text("Send me\npictures!")
                            .font(.system(size: 34, weight: .bold))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white)
                    .frame(width: 280, height: 280)
                    .background(
                        Circle()
                            .fill(Color.pink.gradient)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSending)
                .sensoryFeedback(.success, trigger: showConfirmation)

                if showConfirmation {
                    Text("Request sent! Your family\nwill send photos soon.")
                        .font(.title2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.green)
                        .transition(.opacity.combined(with: .scale))
                }

                if let time = lastRequestTime {
                    Text("Last request: \(time.formatted(date: .omitted, time: .shortened))")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if fulfilledPhotosExist {
                    Button {
                        showGallery = true
                    } label: {
                        Label("View Photos", systemImage: "photo.on.rectangle")
                            .font(.title2)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(16)
                    }
                    .padding(.horizontal, 40)
                }
            }
            .padding()
            .animation(.easeInOut, value: showConfirmation)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showSwitchRoleAlert = true
                        } label: {
                            Label("Switch to Family", systemImage: "arrow.left.arrow.right")
                        }

                        Divider()

                        Link(destination: URL(string: "https://grandmawantspics.com/privacy")!) {
                            Label("Privacy Policy", systemImage: "doc.text")
                        }

                        #if DEBUG
                        Divider()

                        Button(role: .destructive) {
                            appVM.resetAll()
                        } label: {
                            Label("Reset App", systemImage: "trash")
                        }
                        #endif
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showGallery) {
                GrandmaGalleryView()
                    .environmentObject(appVM)
            }
            .onChange(of: appVM.pendingDeepAction) { _, action in
                if action == .openGallery {
                    showGallery = true
                    appVM.pendingDeepAction = nil
                }
            }
            .alert("Switch to Family Mode?", isPresented: $showSwitchRoleAlert) {
                Button("Switch") {
                    appVM.switchRole()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will change the app to Family mode. You can always switch back.")
            }
            .alert("Request Already Pending", isPresented: $showDuplicateAlert) {
                Button("Send Anyway") {
                    Task { await sendRequest() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You already have a pending request. Send another one?")
            }
        }
    }

    private func sendRequest() async {
        isSending = true
        _ = try? await appVM.store.createRequest()
        lastRequestTime = Date()
        showConfirmation = true

        if !hasPromptedNotifications {
            hasPromptedNotifications = true
            await appVM.setupNotifications()
        }

        isSending = false

        // Auto-dismiss confirmation
        try? await Task.sleep(for: .seconds(3))
        showConfirmation = false
    }
}
