import SwiftUI
import StoreKit

struct SubscriptionView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var showManageSheet = false

    private var manager: SubscriptionManager { appVM.subscriptionManager }

    private var expiringPhotoCount: Int {
        guard appVM.isFreeTier else { return 0 }
        let photos = appVM.store.allPhotos.values.flatMap { $0 }
        return photos.filter { !$0.isExpired && $0.daysUntilExpiry <= 7 }.count
    }

    private var subtitle: String {
        if expiringPhotoCount == 1 {
            return "1 photo is set to expire soon. Keep it from being removed."
        } else if expiringPhotoCount > 1 {
            return "\(expiringPhotoCount) photos are set to expire soon. Keep them from being removed."
        }
        return "Photos don't expire while you're subscribed."
    }

    /// Monthly product first, then yearly.
    private var sortedProducts: [Product] {
        manager.products.sorted { a, _ in a.id == SubscriptionManager.monthlyProductId }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // MARK: Header
                    VStack(spacing: 12) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.yellow)
                        Text("Keep Grandma's Memories Safe")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text(subtitle)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 32)
                    .padding(.horizontal, 24)

                    // MARK: Feature Comparison
                    VStack(spacing: 0) {
                        HStack {
                            Spacer()
                            Text("Free")
                                .frame(width: 90, alignment: .trailing)
                                .foregroundStyle(.secondary)
                            Text("Premium")
                                .frame(width: 100, alignment: .trailing)
                                .foregroundStyle(.pink)
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)

                        Divider().padding(.horizontal, 16)

                        comparisonRow(
                            feature: "Photo storage",
                            free: "Expires after\n30 days",
                            premium: "No expiration\nwhile active"
                        )
                        Divider().padding(.horizontal, 16)
                        comparisonRow(
                            feature: "Recovery window",
                            free: "Not\navailable",
                            premium: "Restore\nrecent pics"
                        )
                        Divider().padding(.horizontal, 16)
                        comparisonRow(
                            feature: "Photo requests",
                            free: "Unlimited",
                            premium: "Unlimited"
                        )
                    }
                    .padding(.vertical, 8)
                    .background(Color(.systemGroupedBackground))
                    .cornerRadius(16)
                    .padding(.horizontal)

                    // MARK: Purchase / Subscribed State
                    if manager.isSubscribed {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.green)
                            Text("You're subscribed!")
                                .font(.headline)
                            Text("Your photos are kept while subscribed.")
                                .foregroundStyle(.secondary)
                            Button {
                                showManageSheet = true
                            } label: {
                                Text("Manage Subscription")
                                    .font(.subheadline)
                                    .foregroundStyle(.blue)
                            }
                            .padding(.top, 4)
                        }
                        .padding()
                    } else {
                        VStack(spacing: 16) {
                            ForEach(sortedProducts) { product in
                                purchaseButton(for: product)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 4)

                        Button("Restore Purchases") {
                            Task { await manager.restorePurchases() }
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .padding(.horizontal)
                    }

                    // MARK: Fine Print
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Subscription renews automatically unless canceled.")
                        Text("Photos remain available while subscribed. If your subscription ends, new expirations follow the Free plan.")
                        Text("Recently removed photos can be restored within 30 days.")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .manageSubscriptionsSheet(isPresented: $showManageSheet)
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Purchase Button

    private func purchaseButton(for product: Product) -> some View {
        let isYearly = product.id == SubscriptionManager.yearlyProductId
        return Button {
            Task { await purchase(product) }
        } label: {
            VStack(spacing: 4) {
                Text(isYearly ? "Choose Yearly" : "Choose Monthly")
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(product.displayPrice)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                    if isYearly {
                        Text("· Save $20 vs monthly")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.pink.gradient)
            .foregroundStyle(.white)
            .cornerRadius(14)
            .overlay(alignment: .topTrailing) {
                if isYearly {
                    Text("Best Value")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.yellow)
                        .foregroundStyle(.black)
                        .cornerRadius(8)
                        .offset(x: -12, y: -10)
                }
            }
        }
        .disabled(isPurchasing)
        .padding(.top, isYearly ? 8 : 0) // room for the badge to breathe
    }

    // MARK: - Comparison Row

    private func comparisonRow(feature: String, free: String, premium: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(feature)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(free)
                .frame(width: 90, alignment: .trailing)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
            Text(premium)
                .frame(width: 100, alignment: .trailing)
                .multilineTextAlignment(.trailing)
                .fontWeight(.semibold)
                .foregroundStyle(.pink)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Purchase Action

    private func purchase(_ product: Product) async {
        isPurchasing = true
        errorMessage = nil
        do {
            let success = try await manager.purchase(product)
            if success {
                await appVM.syncSubscriptionTier()
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
        }
        isPurchasing = false
    }
}
