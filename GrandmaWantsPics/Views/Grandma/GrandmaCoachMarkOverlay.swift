import SwiftUI

struct GrandmaCoachMarkOverlay: View {
    @Binding var currentStep: Int
    let buttonFrame: CGRect
    let onDismiss: () -> Void

    private let totalSteps = 2

    var body: some View {
        ZStack {
            SpotlightBackground(
                spotlightFrame: currentStep == 0 ? buttonFrame : .zero,
                showSpotlight: currentStep == 0
            )
            .ignoresSafeArea()
            .onTapGesture { }

            if currentStep == 0 {
                buttonTooltip
            } else {
                finalCard
            }

            VStack {
                Spacer()
                HStack(spacing: 10) {
                    ForEach(0..<totalSteps, id: \.self) { index in
                        Circle()
                            .fill(index == currentStep ? Color.pink : Color.white.opacity(0.5))
                            .frame(width: 10, height: 10)
                    }
                }
                .padding(.bottom, 50)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentStep)
    }

    // MARK: - Step 0: Button tooltip

    private var buttonTooltip: some View {
        let screenHeight = UIScreen.main.bounds.height
        let showAbove = buttonFrame.midY > screenHeight * 0.55

        return VStack(spacing: 0) {
            if !showAbove {
                Spacer().frame(height: buttonFrame.maxY + 24)
            }

            VStack(spacing: 16) {
                Text("Ask for Pictures!")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)

                Text("Tap this button whenever you'd like to see photos from your family. They'll get a notification right away!")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: advance) {
                    Text("Next")
                        .font(.headline.bold())
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                        .background(Color.pink)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 14, y: 4)
            )
            .padding(.horizontal, 28)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: showAbove ? .bottom : .top)
        .padding(.bottom, showAbove ? screenHeight - buttonFrame.minY + 24 : 0)
    }

    // MARK: - Step 1: Final card

    private var finalCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 52))
                .foregroundStyle(.pink)

            Text("Your Photos Will Appear Here")
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            Text("When your family sends photos, a \"View Photos\" button will appear. Tap it anytime to see them!")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: advance) {
                Text("Got it!")
                    .font(.headline.bold())
                    .padding(.horizontal, 48)
                    .padding(.vertical, 16)
                    .background(Color.pink)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.2), radius: 16, y: 4)
        )
        .padding(.horizontal, 32)
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
