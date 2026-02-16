import Foundation
import SwiftUI

/// Base class for family store implementations.
/// LocalFamilyStore (Phase 0) and FirebaseFamilyStore (Phase 1) both extend this.
/// Views observe this through AppViewModel — changes to `requests` or `allPhotos` trigger UI updates.
class FamilyStore: ObservableObject {
    @Published var requests: [PhotoRequest] = []
    @Published var allPhotos: [String: [Photo]] = [:] // keyed by requestId
    var familyId: String?

    func createFamily() async throws -> Family { fatalError("Subclass must implement") }
    func joinFamily(pairingCode: String) async throws -> Family { fatalError("Subclass must implement") }
    func createRequest() async throws -> PhotoRequest { fatalError("Subclass must implement") }
    func fulfillRequest(_ requestId: String, imageDataList: [Data]) async throws { fatalError("Subclass must implement") }
    func photos(for requestId: String) -> [Photo] { allPhotos[requestId] ?? [] }
    func loadImageData(for photo: Photo) async throws -> Data? { nil }
    func deletePhoto(_ photo: Photo, fromRequest requestId: String) async throws { fatalError("Subclass must implement") }
    func updateSubscriptionTier(_ tier: SubscriptionTier) async throws { fatalError("Subclass must implement") }
    func startListening() {}
    func stopListening() {}
}
