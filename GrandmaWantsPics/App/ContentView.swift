import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appVM: AppViewModel

    var body: some View {
        Group {
            if let role = appVM.currentRole {
                if appVM.isPaired {
                    switch role {
                    case .grandma:
                        GrandmaHomeView()
                    case .adult:
                        AdultInboxView()
                    }
                } else {
                    PairingView(role: role)
                }
            } else {
                RoleSelectionView()
            }
        }
        .task {
            await appVM.performStartupCleanupIfNeeded()
        }
    }
}
