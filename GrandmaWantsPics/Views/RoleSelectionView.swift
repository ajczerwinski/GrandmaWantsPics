import SwiftUI

struct RoleSelectionView: View {
    @EnvironmentObject var appVM: AppViewModel

    var body: some View {
        VStack(spacing: 40) {
            Text("Welcome!")
                .font(.system(size: 36, weight: .bold))

            Text("Who's using this device?")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(spacing: 24) {
                Button {
                    appVM.selectRole(.grandma)
                } label: {
                    VStack(spacing: 8) {
                        Text("👵")
                            .font(.system(size: 60))
                        Text("I'm Grandma")
                            .font(.title)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .background(Color.pink.opacity(0.15))
                    .cornerRadius(24)
                }
                .buttonStyle(.plain)

                Button {
                    appVM.selectRole(.adult)
                } label: {
                    VStack(spacing: 8) {
                        Text("👨‍👩‍👧")
                            .font(.system(size: 60))
                        Text("I'm Family")
                            .font(.title)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(24)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)
        }
        .padding()
    }
}
