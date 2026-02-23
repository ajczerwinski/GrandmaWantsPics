import SwiftUI

struct CoachMarkOverlay: View {
    @Binding var currentStep: Int
    let spotlightFrames: [CGRect]  // camera, inbox, gear
    let onDismiss: () -> Void

    private let totalSteps = 4

    private var steps: [(title: String, description: String)] {
        [
            ("Send Photos", "Tap here to send photos to Grandma anytime."),
            ("Your Inbox", "When Grandma requests photos, they'll appear here for you to fulfill."),
            ("Settings", "Manage your subscription and account settings here."),
            ("Protect Your Account", "Tip: Link an email in Settings > Account so you can recover your photos if you ever reinstall.")
        ]
    }

    var body: some View {
        ZStack {
            // Dimmed background with spotlight cutout
            SpotlightBackground(
                spotlightFrame: currentStep < spotlightFrames.count ? spotlightFrames[currentStep] : .zero,
                showSpotlight: currentStep < 3
            )
            .ignoresSafeArea()
            .onTapGesture {
                // Prevent taps from passing through
            }

            // Tooltip
            if currentStep < 3 {
                spotlightTooltip
            } else {
                centeredCard
            }

            // Step dots
            VStack {
                Spacer()
                stepDots
                    .padding(.bottom, 50)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentStep)
    }

    // MARK: - Spotlight Tooltip

    private var spotlightTooltip: some View {
        let frame = currentStep < spotlightFrames.count ? spotlightFrames[currentStep] : .zero
        let step = steps[currentStep]
        let showAbove = frame.midY > UIScreen.main.bounds.height / 2

        return VStack(spacing: 0) {
            if !showAbove {
                Spacer().frame(height: frame.maxY + 16)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(step.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(step.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    Button(action: advance) {
                        Text(currentStep == totalSteps - 1 ? "Got it!" : "Next")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Color.pink)
                            .foregroundStyle(.white)
                            .cornerRadius(8)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            )
            .padding(.horizontal, 24)

            if showAbove {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: showAbove ? .bottom : .top)
        .padding(.bottom, showAbove ? UIScreen.main.bounds.height - frame.minY + 16 : 0)
    }

    // MARK: - Centered Card (Step 4)

    private var centeredCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text(steps[3].title)
                .font(.title3.bold())

            Text(steps[3].description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: advance) {
                Text("Got it!")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.pink)
                    .foregroundStyle(.white)
                    .cornerRadius(8)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.2), radius: 16, y: 4)
        )
        .padding(.horizontal, 40)
    }

    // MARK: - Step Dots

    private var stepDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index == currentStep ? Color.pink : Color.white.opacity(0.5))
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Actions

    private func advance() {
        if currentStep < totalSteps - 1 {
            currentStep += 1
        } else {
            onDismiss()
        }
    }
}

// MARK: - Spotlight Background Shape

private struct SpotlightBackground: View {
    let spotlightFrame: CGRect
    let showSpotlight: Bool

    var body: some View {
        SpotlightShape(spotlightFrame: spotlightFrame, showSpotlight: showSpotlight)
            .fill(style: FillStyle(eoFill: true))
            .foregroundStyle(Color.black.opacity(0.6))
    }
}

private struct SpotlightShape: Shape {
    let spotlightFrame: CGRect
    let showSpotlight: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)

        if showSpotlight && spotlightFrame != .zero {
            let insetFrame = spotlightFrame.insetBy(dx: -8, dy: -8)
            path.addRoundedRect(
                in: insetFrame,
                cornerSize: CGSize(width: 10, height: 10)
            )
        }

        return path
    }
}
