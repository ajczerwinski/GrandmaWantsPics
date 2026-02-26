import SwiftUI

struct ExpirationBannerView: View {
    @EnvironmentObject var appVM: AppViewModel
    let onPrimaryAction: () -> Void

    var body: some View {
        switch appVM.expirationBannerState {
        case .none:
            EmptyView()
        case .sevenDayWarning:
            bannerRow(
                title: "Some photos expire in 7 days",
                body: "Upgrade to keep them available for Grandma.",
                buttonLabel: "Keep Photos",
                icon: "clock.badge.exclamationmark",
                iconColor: .orange
            )
        case .removed:
            bannerRow(
                title: "Photos were removed today",
                body: "You can restore them within 30 days.",
                buttonLabel: "Restore Photos",
                icon: "arrow.counterclockwise.circle.fill",
                iconColor: .pink
            )
        case .finalWarning:
            bannerRow(
                title: "Last chance to restore these photos",
                body: "They'll be permanently deleted in 3 days.",
                buttonLabel: "Restore Before Deletion",
                icon: "exclamationmark.triangle.fill",
                iconColor: .red
            )
        }
    }

    private func bannerRow(title: String, body: String, buttonLabel: String,
                           icon: String, iconColor: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(iconColor).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(body).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(buttonLabel) { onPrimaryAction() }
                .font(.caption.bold()).buttonStyle(.borderedProminent).tint(.pink)
            Button { appVM.dismissExpirationBanner() } label: {
                Image(systemName: "xmark").font(.caption).foregroundStyle(.secondary)
            }.buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
