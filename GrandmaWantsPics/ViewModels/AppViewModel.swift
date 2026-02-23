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
    @Published var showSignIn: Bool = false
    @Published var isRecoveringAccount: Bool = false
    @Published var recoveryError: String?
    @Published var showAccountNudge: Bool = false

    let store: FamilyStore
    let authService = AuthService()
    let subscriptionManager = SubscriptionManager()
    let notificationService = NotificationService.shared
    @Published private(set) var galleryDataManager: GalleryDataManager?
    private(set) var imageCacheService: ImageCacheService?

    private let roleKey = "selectedRole"
    private let pairedKey = "isPaired"
    private let pairingCodeKey = "pendingPairingCode"
    private let hasSeenAccountNudgeKey = "hasSeenAccountNudge"
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
            let firebaseStore = FirebaseFamilyStore()
            firebaseStore.authService = authService
            self.store = firebaseStore
        } else {
            self.store = LocalFamilyStore()
        }

        // Forward store's objectWillChange so views update
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Forward authService's objectWillChange so views update
        authService.objectWillChange
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
        pairingCode = UserDefaults.standard.string(forKey: pairingCodeKey)

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

        // Initialize image cache service for Firebase mode
        if AppConfig.useFirebase {
            self.imageCacheService = ImageCacheService()
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

        // Evict cached images for photos that no longer exist
        let remainingPhotos = store.allPhotos.values.flatMap { $0 }
        imageCacheService?.evictExpired(photos: remainingPhotos)
    }

    // MARK: - Subscription

    func syncSubscriptionTier() async {
        do {
            try await store.updateSubscriptionTier(subscriptionTier)
        } catch {
            #if DEBUG
            print("Failed to sync subscription tier: \(error)")
            #endif
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
            UserDefaults.standard.set(family.pairingCode, forKey: pairingCodeKey)
            // Don't set isPaired yet — let the user see the code first
            // and tap "Continue" to proceed
        } catch {
            #if DEBUG
            print("Create family error: \(error)")
            #endif
        }
    }

    func confirmPairing() {
        isPaired = true
        UserDefaults.standard.set(true, forKey: pairedKey)
        UserDefaults.standard.removeObject(forKey: pairingCodeKey)
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
            #if DEBUG
            print("Join family error: \(error)")
            #endif
            return false
        }
    }

    // MARK: - Account Recovery

    func recoverAccount() async {
        isRecoveringAccount = true
        recoveryError = nil
        defer { isRecoveringAccount = false }

        do {
            guard let familyId = try await authService.recoverFamilyId() else {
                recoveryError = "No family found for this account."
                return
            }

            guard let roleString = try await authService.recoverConnectionRole(),
                  let role = AppRole(rawValue: roleString) else {
                recoveryError = "Could not determine your role."
                return
            }

            // Restore state
            store.familyId = familyId
            UserDefaults.standard.set(familyId, forKey: "firebase_familyId")
            selectRole(role)
            isPaired = true
            UserDefaults.standard.set(true, forKey: pairedKey)
            store.startListening()
            ensureGalleryDataManager()
            syncWidgetData()
            showSignIn = false
            await setupNotifications()
        } catch {
            recoveryError = "Recovery failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Account Nudge

    func triggerAccountNudgeIfNeeded() {
        guard !authService.isLinked,
              !UserDefaults.standard.bool(forKey: hasSeenAccountNudgeKey) else { return }
        showAccountNudge = true
    }

    func dismissAccountNudge() {
        showAccountNudge = false
        UserDefaults.standard.set(true, forKey: hasSeenAccountNudgeKey)
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

        // Set role and attempt to join — only clear clipboard on success
        selectRole(appRole)
        let success = await joinFamily(code: payload.code, asRole: payload.role)

        if success {
            // Clear clipboard only after successful join to prevent re-triggering
            UIPasteboard.general.string = ""
        } else {
            // Reset role so user sees normal selection flow and can retry
            currentRole = nil
            UserDefaults.standard.removeObject(forKey: roleKey)
        }

        return success
    }

    func resetAll() {
        store.stopListening()
        try? authService.signOut()
        currentRole = nil
        isPaired = false
        pairingCode = nil
        showSignIn = false
        isRecoveringAccount = false
        showAccountNudge = false
        galleryDataManager = nil
        imageCacheService?.clearAll()
        UserDefaults.standard.removeObject(forKey: roleKey)
        UserDefaults.standard.removeObject(forKey: pairedKey)
        UserDefaults.standard.removeObject(forKey: pairingCodeKey)
        UserDefaults.standard.removeObject(forKey: "firebase_familyId")
        UserDefaults.standard.removeObject(forKey: hasSeenAccountNudgeKey)
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
