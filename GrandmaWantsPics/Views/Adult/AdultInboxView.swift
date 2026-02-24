import SwiftUI

// MARK: - Preference Key for capturing coach mark anchor frames

private struct CoachMarkFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct AdultInboxView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var selectedRequest: PhotoRequest?
    @State private var showSubscriptionSheet = false
    @State private var showSendPhotosSheet = false
    @State private var showAccountSheet = false
    @State private var showSwitchRoleAlert = false
    @State private var coachMarkStep = 0
    @State private var cameraFrame: CGRect = .zero
    @State private var inboxFrame: CGRect = .zero
    @State private var gearFrame: CGRect = .zero

    var body: some View {
        NavigationStack {
            Group {
                if appVM.store.requests.isEmpty {
                    ContentUnavailableView(
                        "No requests yet",
                        systemImage: "tray",
                        description: Text("When Grandma taps her button, her request will appear here. You can also send photos anytime!")
                    )
                } else {
                    List {
                        if appVM.showAccountNudge && !appVM.authService.isLinked {
                            Section {
                                HStack(spacing: 12) {
                                    Image(systemName: "shield.fill")
                                        .foregroundStyle(.blue)
                                        .font(.title3)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Protect your photos")
                                            .font(.subheadline.bold())
                                        Text("Link an email so you never lose them.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Link Account") {
                                        showAccountSheet = true
                                    }
                                    .font(.caption.bold())
                                    .buttonStyle(.borderedProminent)
                                    .tint(.blue)
                                    Button {
                                        appVM.dismissAccountNudge()
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        if appVM.isFreeTier {
                            Section {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock.badge.exclamationmark")
                                        .foregroundStyle(.orange)
                                        .font(.title3)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Photos expire after 30 days")
                                            .font(.subheadline.bold())
                                        Text("Upgrade to Premium to keep them longer.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Upgrade") {
                                        showSubscriptionSheet = true
                                    }
                                    .font(.caption.bold())
                                    .buttonStyle(.borderedProminent)
                                    .tint(.pink)
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        Section {
                            ForEach(appVM.store.requests) { request in
                                Button {
                                    selectedRequest = request
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(request.fromRole == "adult" ? "Sent Photos" : "Photo Request")
                                                .font(.headline)
                                            Text(request.createdAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        StatusBadge(status: request.status)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: CoachMarkFrameKey.self,
                        value: ["inbox": geo.frame(in: .global)]
                    )
                }
            )
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSendPhotosSheet = true
                    } label: {
                        Image(systemName: "camera.fill")
                            .font(.body)
                            .foregroundStyle(.pink)
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: CoachMarkFrameKey.self,
                                value: ["camera": geo.frame(in: .global)]
                            )
                        }
                    )
                }
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

                        Button {
                            showSubscriptionSheet = true
                        } label: {
                            if appVM.isFreeTier {
                                Label("Upgrade to Premium", systemImage: "star")
                            } else {
                                Label("Manage Subscription", systemImage: "star.fill")
                            }
                        }

                        Divider()

                        Button {
                            appVM.resetCoachMarks()
                            appVM.showCoachMarks = true
                            coachMarkStep = 0
                        } label: {
                            Label("How to Use", systemImage: "questionmark.circle")
                        }

                        Divider()

                        Button {
                            showSwitchRoleAlert = true
                        } label: {
                            Label("Switch to Grandma", systemImage: "arrow.left.arrow.right")
                        }

                        #if DEBUG
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
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: CoachMarkFrameKey.self,
                                value: ["gear": geo.frame(in: .global)]
                            )
                        }
                    )
                }
            }
            .onPreferenceChange(CoachMarkFrameKey.self) { frames in
                if let f = frames["camera"] { cameraFrame = f }
                if let f = frames["inbox"] { inboxFrame = f }
                if let f = frames["gear"] { gearFrame = f }
            }
            .alert("Switch to Grandma Mode?", isPresented: $showSwitchRoleAlert) {
                Button("Switch") {
                    appVM.switchRole()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will change the app to Grandma mode. You can always switch back.")
            }
            .sheet(item: $selectedRequest) { request in
                AdultRequestDetailView(request: request)
                    .environmentObject(appVM)
            }
            .sheet(isPresented: $showSendPhotosSheet) {
                AdultSendPhotosView()
                    .environmentObject(appVM)
            }
            .sheet(isPresented: $showSubscriptionSheet) {
                SubscriptionView()
                    .environmentObject(appVM)
            }
            .sheet(isPresented: $showAccountSheet, onDismiss: {
                if appVM.authService.isLinked {
                    appVM.dismissAccountNudge()
                }
            }) {
                AccountView()
                    .environmentObject(appVM)
            }
            .overlay {
                if appVM.showCoachMarks {
                    CoachMarkOverlay(
                        currentStep: $coachMarkStep,
                        spotlightFrames: [cameraFrame, inboxFrame, gearFrame],
                        onDismiss: {
                            appVM.dismissCoachMarks()
                            coachMarkStep = 0
                        }
                    )
                }
            }
            .onAppear {
                appVM.triggerCoachMarksIfNeeded()
            }
        }
    }
}

struct StatusBadge: View {
    let status: PhotoRequest.Status

    var body: some View {
        Text(status == .pending ? "Pending" : "Sent")
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(status == .pending ? Color.orange.opacity(0.2) : Color.green.opacity(0.2))
            .foregroundStyle(status == .pending ? .orange : .green)
            .cornerRadius(8)
    }
}
