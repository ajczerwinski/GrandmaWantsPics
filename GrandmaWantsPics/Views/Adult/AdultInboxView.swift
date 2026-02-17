import SwiftUI

struct AdultInboxView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var selectedRequest: PhotoRequest?
    @State private var showSubscriptionSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if appVM.store.requests.isEmpty {
                    ContentUnavailableView(
                        "No requests yet",
                        systemImage: "tray",
                        description: Text("When Grandma taps her button,\nher request will appear here.")
                    )
                } else {
                    List {
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
                                            Text("Photo Request")
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
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
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

                        Button(role: .destructive) {
                            appVM.switchRole()
                        } label: {
                            Label("Switch to Grandma", systemImage: "arrow.left.arrow.right")
                        }

                        Button(role: .destructive) {
                            appVM.resetAll()
                        } label: {
                            Label("Reset App", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(item: $selectedRequest) { request in
                AdultRequestDetailView(request: request)
                    .environmentObject(appVM)
            }
            .sheet(isPresented: $showSubscriptionSheet) {
                SubscriptionView()
                    .environmentObject(appVM)
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
