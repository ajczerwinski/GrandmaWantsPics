import SwiftUI

/// Side-by-side demo: Grandma on the left, Adult on the right.
/// Both share the same store so actions propagate instantly.
struct DemoSplitView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var selectedRequest: PhotoRequest?

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Grandma Side
            grandmaSide
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))

            Divider()

            // MARK: - Adult Side
            adultSide
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
        }
    }

    // MARK: - Grandma Panel

    @ViewBuilder
    private var grandmaSide: some View {
        GrandmaHomeView()
            .environmentObject(appVM)
            .overlay(alignment: .top) {
                Text("Grandma's Device")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.pink.cornerRadius(12))
                    .padding(.top, 8)
            }
    }

    // MARK: - Adult Panel

    @ViewBuilder
    private var adultSide: some View {
        NavigationStack {
            Group {
                if appVM.store.requests.isEmpty {
                    ContentUnavailableView(
                        "No requests yet",
                        systemImage: "tray",
                        description: Text("When Grandma taps her button,\nher request will appear here.")
                    )
                } else {
                    List(appVM.store.requests) { request in
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
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        appVM.resetAll()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(item: $selectedRequest) { request in
                AdultRequestDetailView(request: request)
                    .environmentObject(appVM)
            }
        }
        .overlay(alignment: .top) {
            Text("Family's Device")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.cornerRadius(12))
                .padding(.top, 8)
        }
    }
}
