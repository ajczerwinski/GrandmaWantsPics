import SwiftUI

// MARK: - Preference Key for capturing coach mark anchor frames

private struct CoachMarkFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private enum InboxFilter: String, CaseIterable {
    case active = "Active"
    case history = "History"
}

struct AdultInboxView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var selectedRequest: PhotoRequest?
    @State private var showSubscriptionSheet = false
    @State private var showSendPhotosSheet = false
    @State private var showAccountSheet = false
    @State private var showSwitchRoleAlert = false
    @State private var showLeaveAlert = false
    @State private var requestToDelete: PhotoRequest?
    @State private var coachMarkStep = 0
    @State private var inboxFilter: InboxFilter = .active

    private static let maxDisplayedRequests = 20

    private var filteredRequests: [PhotoRequest] {
        switch inboxFilter {
        case .active:
            return appVM.store.requests.filter { $0.status == .pending }
        case .history:
            return appVM.store.requests.filter { $0.status == .fulfilled }
        }
    }

    private var displayedRequests: [PhotoRequest] {
        Array(filteredRequests.prefix(Self.maxDisplayedRequests))
    }

    private var hiddenRequestCount: Int {
        max(0, filteredRequests.count - Self.maxDisplayedRequests)
    }

    @State private var cameraFrame: CGRect = .zero
    @State private var inboxFrame: CGRect = .zero
    @State private var gearFrame: CGRect = .zero

    @ViewBuilder private var filterPickerSection: some View {
        Section {
            Picker("Filter", selection: $inboxFilter) {
                ForEach(InboxFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        }
    }

    @ViewBuilder private var accountNudgeSection: some View {
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
    }

    @ViewBuilder private var expirationSection: some View {
        if appVM.expirationBannerVisible {
            Section {
                ExpirationBannerView(onPrimaryAction: { showSubscriptionSheet = true })
            }
        }
    }

    @ViewBuilder private var requestsSection: some View {
        if displayedRequests.isEmpty {
            Section {
                ContentUnavailableView(
                    inboxFilter == .active ? "No pending requests" : "No history yet",
                    systemImage: inboxFilter == .active ? "tray" : "clock",
                    description: Text(inboxFilter == .active
                        ? "When Grandma taps her button, her request will appear here."
                        : "Fulfilled requests will appear here once you've sent photos.")
                )
                .listRowBackground(Color.clear)
            }
        }
        Section {
            ForEach(displayedRequests) { request in
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
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if request.status == .pending {
                        Button(role: .destructive) {
                            Task { try? await appVM.store.deleteRequest(request) }
                        } label: {
                            Label("Dismiss", systemImage: "xmark")
                        }
                    } else {
                        Button(role: .destructive) {
                            requestToDelete = request
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .contextMenu {
                    if request.status == .pending {
                        Button(role: .destructive) {
                            Task { try? await appVM.store.deleteRequest(request) }
                        } label: {
                            Label("Dismiss Request", systemImage: "xmark.circle")
                        }
                    } else {
                        Button {
                            selectedRequest = request
                        } label: {
                            Label("Open", systemImage: "eye")
                        }
                        Button(role: .destructive) {
                            requestToDelete = request
                        } label: {
                            Label("Delete Request & Photos", systemImage: "trash")
                        }
                    }
                }
            }
            if hiddenRequestCount > 0 {
                Text("\(hiddenRequestCount) older request\(hiddenRequestCount == 1 ? "" : "s") not shown")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
        }
    }

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
                        filterPickerSection
                        accountNudgeSection
                        expirationSection
                        requestsSection
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

                        Divider()

                        Link(destination: URL(string: "https://grandmawantspics.com/privacy")!) {
                            Label("Privacy Policy", systemImage: "doc.text")
                        }

                        Link(destination: URL(string: "https://grandmawantspics.com/csam")!) {
                            Label("Child Safety Policy", systemImage: "hand.raised")
                        }

                        Divider()

                        Button {
                            showSwitchRoleAlert = true
                        } label: {
                            Label("Switch to Grandma", systemImage: "arrow.left.arrow.right")
                        }

                        Button(role: .destructive) {
                            showLeaveAlert = true
                        } label: {
                            Label("Leave Family", systemImage: "rectangle.portrait.and.arrow.right")
                        }

                        #if DEBUG
                        Divider()
                        Menu("Test Expiration") {
                            Button("Phase 1: 7-Day Warning") {
                                appVM.simulateBannerPhase(.sevenDayWarning(count: 2))
                            }
                            Button("Phase 2: Photos Removed") {
                                appVM.simulateBannerPhase(.removed(count: 1))
                            }
                            Button("Phase 3: Final Warning") {
                                appVM.simulateBannerPhase(.finalWarning(count: 1))
                            }
                            Divider()
                            Button("Inject Test Photos (Inline Labels)") {
                                appVM.injectTestExpirationPhotos()
                            }
                            Button("Clear Banner Override") {
                                appVM.debugBannerOverride = nil
                            }
                        }
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
            .alert("Delete Request & Photos?", isPresented: Binding(
                get: { requestToDelete != nil },
                set: { if !$0 { requestToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    guard let req = requestToDelete else { return }
                    requestToDelete = nil
                    Task { try? await appVM.store.deleteRequest(req) }
                }
                Button("Cancel", role: .cancel) { requestToDelete = nil }
            } message: {
                Text("These photos will be permanently removed from Grandma's gallery.")
            }
            .alert("Switch to Grandma Mode?", isPresented: $showSwitchRoleAlert) {
                Button("Switch") {
                    appVM.switchRole()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will change the app to Grandma mode. You can always switch back.")
            }
            .alert("Leave Family?", isPresented: $showLeaveAlert) {
                Button("Leave Family", role: .destructive) {
                    appVM.resetAll()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will disconnect your app from this family. To reconnect, you'll need a new invite link.")
            }
            .sheet(item: $selectedRequest) { request in
                AdultRequestDetailView(request: request)
                    .environmentObject(appVM)
            }
            .sheet(isPresented: $showSendPhotosSheet) {
                AdultSendPhotosView()
                    .environmentObject(appVM)
            }
            .fullScreenCover(isPresented: $appVM.showFirstPhotosPrompt) {
                FirstPhotosPromptView()
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
            .onAppear {
                appVM.triggerCoachMarksIfNeeded()
            }
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
