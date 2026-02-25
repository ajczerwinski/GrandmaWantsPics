import SwiftUI
import StoreKit

struct SubscriptionView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var showManageSheet = false

    private var manager: SubscriptionManager { appVM.subscriptionManager }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.yellow)
                        Text("GrandmaWantsPics Premium")
                            .font(.title2.bold())
                        Text("Keep your photos as long as you're subscribed")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 32)

                    // Comparison
                    VStack(spacing: 16) {
                        comparisonRow(
                            feature: "Photo requests",
                            free: "Unlimited",
                            premium: "Unlimited"
                        )
                        comparisonRow(
                            feature: "Photo storage",
                            free: "30 days",
                            premium: "While subscribed"
                        )
                    }
                    .padding()
                    .background(Color(.systemGroupedBackground))
                    .cornerRadius(16)
                    .padding(.horizontal)

                    if manager.isSubscribed {
                        // Active subscription
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
                        // Purchase buttons
                        VStack(spacing: 12) {
                            ForEach(manager.products.sorted(by: { $0.price < $1.price })) { product in
                                Button {
                                    Task { await purchase(product) }
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(product.displayName)
                                            .font(.headline)
                                        Text(product.displayPrice)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.pink.gradient)
                                    .foregroundStyle(.white)
                                    .cornerRadius(14)
                                }
                                .disabled(isPurchasing)
                            }
                        }
                        .padding(.horizontal, 32)

                        // Restore
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
                    }

                    Spacer()
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

    private func comparisonRow(feature: String, free: String, premium: String) -> some View {
        HStack {
            Text(feature)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(free)
                .frame(width: 70)
                .foregroundStyle(.secondary)
            Text(premium)
                .frame(width: 90, alignment: .trailing)
                .multilineTextAlignment(.trailing)
                .fontWeight(.semibold)
                .foregroundStyle(.pink)
        }
        .font(.subheadline)
    }

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
