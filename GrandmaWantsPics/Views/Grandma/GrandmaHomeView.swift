import SwiftUI

struct GrandmaHomeView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var showConfirmation = false
    @State private var showGallery = false
    @State private var showAccountSheet = false
    @State private var lastRequestTime: Date?
    @State private var hasPromptedNotifications = false

    private var fulfilledPhotosExist: Bool {
        appVM.store.requests.contains(where: { $0.status == .fulfilled })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Button {
                    Task {
                        _ = try? await appVM.store.createRequest()
                        lastRequestTime = Date()
                        showConfirmation = true

                        // Prompt for notifications after first request
                        if !hasPromptedNotifications {
                            hasPromptedNotifications = true
                            await appVM.setupNotifications()
                        }

                        // Auto-dismiss confirmation
                        try? await Task.sleep(for: .seconds(3))
                        showConfirmation = false
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
                            showAccountSheet = true
                        } label: {
                            if appVM.authService.isLinked {
                                Label("Account", systemImage: "person.crop.circle.badge.checkmark")
                            } else {
                                Label("Protect Account", systemImage: "shield")
                            }
                        }

                        #if DEBUG
                        Divider()

                        Button {
                            appVM.switchRole()
                        } label: {
                            Label("Switch to Family", systemImage: "arrow.left.arrow.right")
                        }

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
            .sheet(isPresented: $showAccountSheet) {
                AccountView()
                    .environmentObject(appVM)
            }
        }
    }
}
