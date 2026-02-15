import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appVM: AppViewModel

    var body: some View {
        if let role = appVM.currentRole {
            if role == .demo {
                DemoSplitView()
            } else if appVM.isPaired {
                switch role {
                case .grandma:
                    GrandmaHomeView()
                case .adult:
                    AdultInboxView()
                case .demo:
                    EmptyView() // handled above
                }
            } else {
                PairingView(role: role)
            }
        } else {
            RoleSelectionView()
        }
    }
}
