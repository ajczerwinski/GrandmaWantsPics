import Foundation
import SwiftUI
import UIKit
import Combine

@MainActor
final class AppViewModel: ObservableObject {

    @Published var currentRole: AppRole?
    @Published var isPaired: Bool = false
    @Published var pairingCode: String?
    @Published var isCheckingClipboard: Bool = false

    let store: FamilyStore
    let subscriptionManager = SubscriptionManager()
    let notificationService = NotificationService.shared
    @Published private(set) var galleryDataManager: GalleryDataManager?

    private let roleKey = "selectedRole"
    private let pairedKey = "isPaired"
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Subscription Tier

    var subscriptionTier: SubscriptionTier {
        subscriptionManager.isSubscribed ? .premium : .free
    }

    var isFreeTier: Bool {
        subscriptionTier == .free
    }

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

        // Forward subscriptionManager's objectWillChange so views update
        subscriptionManager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Sync widget data whenever store state changes (debounced)
        store.objectWillChange
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.syncWidgetData()
            }
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

        // Initialize gallery data manager if familyId is available
        if let familyId = store.familyId {
            let manager = GalleryDataManager(familyId: familyId)
            self.galleryDataManager = manager
            manager.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }

        // Load products and check subscription status
        Task {
            await subscriptionManager.loadProducts()
            await subscriptionManager.checkSubscriptionStatus()
        }

        // Set up push notifications for already-paired users
        if isPaired {
            Task { await setupNotifications() }
        }

        // Initial widget sync
        syncWidgetData()
    }

    // MARK: - Widget

    private func syncWidgetData() {
        let requests = store.requests
        let pending = requests.filter { $0.status == .pending }
        let fulfilled = requests.filter { $0.status == .fulfilled }

        let data = WidgetData(
            role: currentRole?.rawValue,
            isPaired: isPaired,
            pendingRequestCount: pending.count,
            oldestPendingRequestDate: pending.map(\.createdAt).min(),
            lastFulfilledDate: fulfilled.compactMap(\.fulfilledAt).max(),
            lastPhotosReceivedDate: fulfilled.compactMap(\.fulfilledAt).max(),
            lastRequestSentDate: requests.map(\.createdAt).max(),
            updatedAt: Date()
        )
        WidgetDataWriter.write(data)
    }

    // MARK: - TTL Cleanup

    func performStartupCleanupIfNeeded() async {
        guard isFreeTier else { return }
        let cleanup = PhotoTTLCleanupService(store: store)
        await cleanup.deleteExpiredPhotos()
    }

    // MARK: - Subscription

    func syncSubscriptionTier() async {
        do {
            try await store.updateSubscriptionTier(subscriptionTier)
        } catch {
            print("Failed to sync subscription tier: \(error)")
        }
    }

    func selectRole(_ role: AppRole) {
        currentRole = role
        UserDefaults.standard.set(role.rawValue, forKey: roleKey)
        syncWidgetData()
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
            // Don't set isPaired yet — let the user see the code first
            // and tap "Continue" to proceed
        } catch {
            print("Create family error: \(error)")
        }
    }

    func confirmPairing() {
        isPaired = true
        UserDefaults.standard.set(true, forKey: pairedKey)
        store.startListening()
        ensureGalleryDataManager()
        syncWidgetData()
        Task { await setupNotifications() }
    }

    func joinFamily(code: String, asRole: String = "grandma") async -> Bool {
        do {
            _ = try await store.joinFamily(pairingCode: code, asRole: asRole)
            isPaired = true
            UserDefaults.standard.set(true, forKey: pairedKey)
            store.startListening()
            ensureGalleryDataManager()
            syncWidgetData()
            await setupNotifications()
            return true
        } catch {
            print("Join family error: \(error)")
            return false
        }
    }

    // MARK: - Share Link

    func generateShareLink() -> URL? {
        guard let code = pairingCode else { return nil }
        let recipientRole = currentRole == .adult ? "grandma" : "adult"
        var components = URLComponents()
        components.scheme = "https"
        components.host = "grandmawantspics.com"
        components.path = "/join"
        components.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "role", value: recipientRole)
        ]
        return components.url
    }

    var shareMessage: String {
        guard let link = generateShareLink() else { return "" }
        return "I set up GrandmaWantsPics for us! Tap this link to connect: \(link)"
    }

    // MARK: - Deep Link

    func handleDeepLink(_ url: URL) {
        let isCustomScheme = url.scheme == AppGroupConstants.deepLinkScheme
        let isUniversalLink = url.scheme == "https" && url.host == "grandmawantspics.com"

        guard isCustomScheme || isUniversalLink else { return }

        // Only handle join links; ignore widget deep links
        let isJoinLink = isCustomScheme ? url.host == "join" : url.path.hasPrefix("/join")
        guard isJoinLink else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let code = components?.queryItems?.first(where: { $0.name == "code" })?.value else { return }
        let role = components?.queryItems?.first(where: { $0.name == "role" })?.value ?? "grandma"

        // Ignore if already paired
        guard !isPaired else { return }

        // Set the role from the link and join
        if let appRole = AppRole(rawValue: role) {
            selectRole(appRole)
        }

        Task {
            _ = await joinFamily(code: code, asRole: role)
        }
    }

    // MARK: - Clipboard Invite

    func checkClipboardForInvite() async -> Bool {
        guard !isPaired, currentRole == nil else { return false }

        guard let clipString = UIPasteboard.general.string,
              let data = clipString.data(using: .utf8) else { return false }

        let payload: ClipboardInvitePayload
        do {
            payload = try JSONDecoder().decode(ClipboardInvitePayload.self, from: data)
        } catch {
            return false
        }

        // Validate namespace
        guard payload.app == "grandmawantspics" else { return false }

        // Validate timestamp (must be < 30 minutes old)
        let age = Int(Date().timeIntervalSince1970) - payload.ts
        guard age >= 0, age < 30 * 60 else { return false }

        // Validate code is a UUID
        guard UUID(uuidString: payload.code) != nil else { return false }

        // Validate role
        guard let appRole = AppRole(rawValue: payload.role) else { return false }

        // Clear clipboard to prevent re-triggering
        UIPasteboard.general.string = ""

        // Set role and join
        selectRole(appRole)
        let success = await joinFamily(code: payload.code, asRole: payload.role)

        if !success {
            // Reset role so user sees normal selection flow
            currentRole = nil
            UserDefaults.standard.removeObject(forKey: roleKey)
        }

        return success
    }

    func resetAll() {
        store.stopListening()
        currentRole = nil
        isPaired = false
        pairingCode = nil
        galleryDataManager = nil
        UserDefaults.standard.removeObject(forKey: roleKey)
        UserDefaults.standard.removeObject(forKey: pairedKey)
        UserDefaults.standard.removeObject(forKey: "firebase_familyId")
        WidgetDataWriter.write(.empty)
    }

    private func ensureGalleryDataManager() {
        guard galleryDataManager == nil, let familyId = store.familyId else { return }
        let manager = GalleryDataManager(familyId: familyId)
        self.galleryDataManager = manager
        manager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Notifications

    func setupNotifications() async {
        guard AppConfig.useFirebase else { return }
        notificationService.configureFCM()
        _ = await notificationService.requestPermission()
        await notificationService.saveFCMToken(store: store)
    }
}
