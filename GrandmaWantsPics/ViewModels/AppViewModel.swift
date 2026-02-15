import Foundation
import SwiftUI
import Combine

final class AppViewModel: ObservableObject {

    @Published var currentRole: AppRole?
    @Published var isPaired: Bool = false
    @Published var pairingCode: String?

    let store: FamilyStore

    private let roleKey = "selectedRole"
    private let pairedKey = "isPaired"
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Choose store based on config
        if AppConfig.useFirebase {
            self.store = FirebaseFamilyStore()
        } else {
            self.store = LocalFamilyStore()
        }

        // Forward store's objectWillChange so views update
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Restore persisted state
        if let raw = UserDefaults.standard.string(forKey: roleKey),
           let role = AppRole(rawValue: raw) {
            currentRole = role
        }
        isPaired = UserDefaults.standard.bool(forKey: pairedKey)

        // In local demo, auto-pair
        if !AppConfig.useFirebase {
            isPaired = true
            UserDefaults.standard.set(true, forKey: pairedKey)
        }

        // In Firebase mode, if we have a familyId, we're paired
        if AppConfig.useFirebase && store.familyId != nil {
            isPaired = true
        }

        // Start listening for real-time updates if paired
        if isPaired {
            store.startListening()
        }
    }

    func selectRole(_ role: AppRole) {
        currentRole = role
        UserDefaults.standard.set(role.rawValue, forKey: roleKey)
    }

    func switchRole() {
        guard let current = currentRole else { return }
        let newRole: AppRole = current == .grandma ? .adult : .grandma
        selectRole(newRole)
    }

    // MARK: - Pairing

    func createFamily() async {
        do {
            let family = try await store.createFamily()
            pairingCode = family.pairingCode
            isPaired = true
            UserDefaults.standard.set(true, forKey: pairedKey)
            store.startListening()
        } catch {
            print("Create family error: \(error)")
        }
    }

    func joinFamily(code: String) async -> Bool {
        do {
            _ = try await store.joinFamily(pairingCode: code)
            isPaired = true
            UserDefaults.standard.set(true, forKey: pairedKey)
            store.startListening()
            return true
        } catch {
            print("Join family error: \(error)")
            return false
        }
    }

    func resetAll() {
        store.stopListening()
        currentRole = nil
        isPaired = false
        pairingCode = nil
        UserDefaults.standard.removeObject(forKey: roleKey)
        UserDefaults.standard.removeObject(forKey: pairedKey)
        UserDefaults.standard.removeObject(forKey: "firebase_familyId")
    }
}
