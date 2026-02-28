import Foundation
import SwiftUI
import UIKit
import Combine

enum ExpirationBannerState {
    case none
    case sevenDayWarning(count: Int)
    case removed(count: Int)
    case finalWarning(count: Int)
}

@MainActor
final class AppViewModel: ObservableObject {

    enum DeepAction: Equatable {
        case openGallery
    }

    @Published var currentRole: AppRole?
    @Published var isPaired: Bool = false
    @Published var pairingCode: String?
    @Published var isCheckingClipboard: Bool = false
    @Published var showSignIn: Bool = false
    @Published var isRecoveringAccount: Bool = false
    @Published var recoveryError: String?
    @Published var showAccountNudge: Bool = false
    @Published var showCoachMarks: Bool = false
    @Published var showFirstPhotosPrompt: Bool = false
    @Published var showGrandmaCoachMarks: Bool = false
    @Published var pendingDeepAction: DeepAction?
    @Published var dismissedSevenDayWarning: Bool = UserDefaults.standard.bool(forKey: "dismissedSevenDayWarning")
    @Published var dismissedRemovedBanner:   Bool = UserDefaults.standard.bool(forKey: "dismissedRemovedBanner")
    @Published var dismissedFinalWarning:    Bool = UserDefaults.standard.bool(forKey: "dismissedFinalWarning")

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
    private let hasSeenCoachMarksKey = "hasSeenCoachMarks"
    private let hasSeenFirstPhotosPromptKey = "hasSeenFirstPhotosPrompt"
    private let hasSeenGrandmaCoachMarksKey = "hasSeenGrandmaCoachMarks"
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

        // Load products, check subscription status, and sync tier to Firestore
        Task {
            await subscriptionManager.loadProducts()
            await subscriptionManager.checkSubscriptionStatus()
            if isPaired {
                await syncSubscriptionTier()
            }
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
        guard !AppConfig.useFirebase else {
            imageCacheService?.evictExpired(photos: store.allPhotos.values.flatMap { $0 })
            return
        }
        let cleanup = PhotoTTLCleanupService(store: store)
        await cleanup.deleteExpiredPhotos()
        imageCacheService?.evictExpired(photos: store.allPhotos.values.flatMap { $0 })
    }

    // MARK: - Subscription

    // MARK: - Expiration

    var expirationBannerState: ExpirationBannerState {
        #if DEBUG
        if let override = debugBannerOverride { return override }
        #endif
        guard isFreeTier else { return .none }
        let photos = store.allPhotos.values.flatMap { $0 }
        let now = Date()

        // Phase 3 — highest priority
        let finalWarn = photos.filter {
            guard let p = $0.purgeAt else { return false }
            return $0.isTrashed && p > now && p <= now.addingTimeInterval(3 * 86400)
        }
        if !finalWarn.isEmpty && !dismissedFinalWarning { return .finalWarning(count: finalWarn.count) }

        // Phase 2
        let removed = photos.filter {
            guard let p = $0.purgeAt else { return false }
            return $0.isTrashed && p > now.addingTimeInterval(3 * 86400)
        }
        if !removed.isEmpty && !dismissedRemovedBanner { return .removed(count: removed.count) }

        // Phase 1
        let expiring = photos.filter { !$0.isTrashed && !$0.isExpired && $0.daysUntilExpiry <= 7 }
        if !expiring.isEmpty && !dismissedSevenDayWarning { return .sevenDayWarning(count: expiring.count) }

        return .none
    }

    var expirationBannerVisible: Bool {
        if case .none = expirationBannerState { return false }
        return true
    }

    func dismissExpirationBanner() {
        #if DEBUG
        if debugBannerOverride != nil {
            debugBannerOverride = nil
            return
        }
        #endif
        switch expirationBannerState {
        case .sevenDayWarning:
            dismissedSevenDayWarning = true
            UserDefaults.standard.set(true, forKey: "dismissedSevenDayWarning")
        case .removed:
            dismissedRemovedBanner = true
            UserDefaults.standard.set(true, forKey: "dismissedRemovedBanner")
        case .finalWarning:
            dismissedFinalWarning = true
            UserDefaults.standard.set(true, forKey: "dismissedFinalWarning")
        case .none: break
        }
    }

    func clearExpirationDismissals() {
        dismissedSevenDayWarning = false
        dismissedRemovedBanner   = false
        dismissedFinalWarning    = false
        UserDefaults.standard.removeObject(forKey: "dismissedSevenDayWarning")
        UserDefaults.standard.removeObject(forKey: "dismissedRemovedBanner")
        UserDefaults.standard.removeObject(forKey: "dismissedFinalWarning")
    }

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

        // Prompt new adult users to send photos before Grandma opens the app
        if currentRole == .adult,
           !UserDefaults.standard.bool(forKey: hasSeenFirstPhotosPromptKey) {
            showFirstPhotosPrompt = true
        }
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

    // MARK: - Coach Marks

    func triggerCoachMarksIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: hasSeenCoachMarksKey) else { return }
        guard !showFirstPhotosPrompt else { return }
        showCoachMarks = true
    }

    func dismissCoachMarks() {
        showCoachMarks = false
        UserDefaults.standard.set(true, forKey: hasSeenCoachMarksKey)
    }

    func resetCoachMarks() {
        UserDefaults.standard.removeObject(forKey: hasSeenCoachMarksKey)
    }

    // MARK: - First Photos Prompt

    func dismissFirstPhotosPrompt() {
        showFirstPhotosPrompt = false
        UserDefaults.standard.set(true, forKey: hasSeenFirstPhotosPromptKey)
        // Chain into the adult coach marks now that the prompt is gone
        triggerCoachMarksIfNeeded()
    }

    // MARK: - Grandma Coach Marks

    func triggerGrandmaCoachMarksIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: hasSeenGrandmaCoachMarksKey) else { return }
        showGrandmaCoachMarks = true
    }

    func dismissGrandmaCoachMarks() {
        showGrandmaCoachMarks = false
        UserDefaults.standard.set(true, forKey: hasSeenGrandmaCoachMarksKey)
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
        return "I set up GrandmaWantsPics for us! 📸 Just tap this link on your phone — it connects your app to mine automatically so you can ask me for pictures whenever you want:\n\(link)"
    }

    // MARK: - Deep Link

    func handleDeepLink(_ url: URL) {
        let isCustomScheme = url.scheme == AppGroupConstants.deepLinkScheme
        let isUniversalLink = url.scheme == "https" && url.host == "grandmawantspics.com"

        guard isCustomScheme || isUniversalLink else { return }

        // Handle gallery navigation deep link (widget tap with photos)
        if isCustomScheme && url.host == "gallery" && isPaired {
            pendingDeepAction = .openGallery
            return
        }

        // Only handle join links for everything else
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
        guard age >= 0, age < 24 * 60 * 60 else { return false }

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
        showFirstPhotosPrompt = false
        showGrandmaCoachMarks = false
        galleryDataManager = nil
        imageCacheService?.clearAll()
        clearExpirationDismissals()
        UserDefaults.standard.removeObject(forKey: roleKey)
        UserDefaults.standard.removeObject(forKey: pairedKey)
        UserDefaults.standard.removeObject(forKey: pairingCodeKey)
        UserDefaults.standard.removeObject(forKey: "firebase_familyId")
        UserDefaults.standard.removeObject(forKey: hasSeenAccountNudgeKey)
        UserDefaults.standard.removeObject(forKey: hasSeenCoachMarksKey)
        UserDefaults.standard.removeObject(forKey: hasSeenFirstPhotosPromptKey)
        UserDefaults.standard.removeObject(forKey: hasSeenGrandmaCoachMarksKey)
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
        notificationService.onNotificationTap = { [weak self] type in
            guard let self else { return }
            if type == "new_photos" {
                pendingDeepAction = .openGallery
            }
        }
        _ = await notificationService.requestPermission()
        await notificationService.saveFCMToken(store: store)
    }

    // MARK: - DEBUG Expiration Testing

    #if DEBUG
    @Published var debugBannerOverride: ExpirationBannerState? = nil

    func simulateBannerPhase(_ state: ExpirationBannerState) {
        debugBannerOverride = state
        clearExpirationDismissals()
    }

    /// Modifies the first available request's photos in-memory to show
    /// inline expiry and trashed rows in AdultRequestDetailView.
    /// The real-time listener will overwrite this on next update.
    func injectTestExpirationPhotos() {
        guard let requestId = store.allPhotos.keys.first,
              var photos = store.allPhotos[requestId], !photos.isEmpty else { return }
        // First photo: expires in 3 days (urgent orange row)
        photos[0].expiresAt = Calendar.current.date(byAdding: .day, value: 3, to: Date())
        // Second photo (if present): trashed, restorable for 20 days (pink row)
        if photos.count >= 2 {
            photos[1].status = "trashed"
            photos[1].trashedAt = Calendar.current.date(byAdding: .day, value: -10, to: Date())
            photos[1].purgeAt = Calendar.current.date(byAdding: .day, value: 20, to: Date())
        }
        // Replace the full dictionary to properly trigger @Published objectWillChange
        var updated = store.allPhotos
        updated[requestId] = photos
        store.allPhotos = updated
    }
    #endif
}
