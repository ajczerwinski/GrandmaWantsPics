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
    @AppStorage("lastGalleryOpenedAt") private var lastGalleryOpenedInterval: Double = 0

    private var fulfilledPhotosExist: Bool {
        appVM.store.requests.contains(where: { $0.status == .fulfilled })
    }

    // Only block if a pending request was sent within the last 24 hours
    private var hasRecentPendingRequest: Bool {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        return appVM.store.requests.contains(where: { $0.status == .pending && $0.createdAt > cutoff })
    }

    private var newPhotoCount: Int {
        let cutoff = lastGalleryOpenedInterval > 0
            ? Date(timeIntervalSince1970: lastGalleryOpenedInterval)
            : Date.distantPast
        return appVM.store.requests
            .filter { $0.status == .fulfilled && ($0.fulfilledAt ?? $0.createdAt) > cutoff }
            .flatMap { appVM.store.photos(for: $0.id) }
            .filter { !$0.isExpired && !$0.isBlocked }
            .count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Button {
                    if hasRecentPendingRequest {
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
                        lastGalleryOpenedInterval = Date().timeIntervalSince1970
                        showGallery = true
                    } label: {
                        Label("View Photos", systemImage: "photo.on.rectangle")
                            .font(.title)
                            .fontWeight(.semibold)
                            .padding(.vertical, 20)
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.opacity(0.15))
                            .cornerRadius(20)
                    }
                    .padding(.horizontal, 32)
                    .overlay(alignment: .topTrailing) {
                        if newPhotoCount > 0 {
                            Text("\(newPhotoCount) new")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.red)
                                .clipShape(Capsule())
                                .offset(x: -40, y: -10)
                        }
                    }
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

                        Link(destination: URL(string: "https://grandmawantspics.com/csam")!) {
                            Label("Child Safety Policy", systemImage: "hand.raised")
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
                    lastGalleryOpenedInterval = Date().timeIntervalSince1970
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
