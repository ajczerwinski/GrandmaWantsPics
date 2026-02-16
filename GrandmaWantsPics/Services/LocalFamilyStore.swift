import Foundation
import SwiftUI

/// Phase 0: All data stored locally on-device. Perfect for demo/simulator testing.
final class LocalFamilyStore: FamilyStore {

    private let storageDir: URL

    override init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storageDir = docs.appendingPathComponent("GrandmaPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        super.init()
        familyId = "local-demo"
        loadFromDisk()
    }

    // MARK: - Family

    override func createFamily() async throws -> Family {
        let family = Family(
            id: "local-demo",
            createdAt: Date(),
            createdByUserId: "local-adult",
            pairingCode: "1234"
        )
        familyId = family.id
        return family
    }

    override func joinFamily(pairingCode: String) async throws -> Family {
        guard pairingCode == "1234" else {
            throw LocalStoreError.invalidPairingCode
        }
        let family = Family(
            id: "local-demo",
            createdAt: Date(),
            createdByUserId: "local-adult",
            pairingCode: pairingCode
        )
        familyId = family.id
        return family
    }

    // MARK: - Requests

    override func createRequest() async throws -> PhotoRequest {
        let request = PhotoRequest(
            id: UUID().uuidString,
            familyId: familyId ?? "local-demo",
            createdAt: Date(),
            createdByUserId: "local-grandma"
        )
        requests.insert(request, at: 0)
        saveToDisk()
        return request
    }

    override func fulfillRequest(_ requestId: String, imageDataList: [Data]) async throws {
        guard let idx = requests.firstIndex(where: { $0.id == requestId }) else {
            throw LocalStoreError.requestNotFound
        }

        var photos: [Photo] = []
        for data in imageDataList {
            let photoId = UUID().uuidString
            let filename = "\(photoId).jpg"
            let fileURL = storageDir.appendingPathComponent(filename)
            try data.write(to: fileURL)

            var photo = Photo(
                id: photoId,
                requestId: requestId,
                createdAt: Date(),
                createdByUserId: "local-adult",
                storagePath: fileURL.path
            )
            photo.imageData = data
            photos.append(photo)
        }

        allPhotos[requestId, default: []].append(contentsOf: photos)
        requests[idx].status = .fulfilled
        requests[idx].fulfilledAt = Date()
        requests[idx].fulfilledByUserId = "local-adult"
        saveToDisk()
    }

    // MARK: - Photos

    override func loadImageData(for photo: Photo) async throws -> Data? {
        if let data = photo.imageData { return data }
        let url = URL(fileURLWithPath: photo.storagePath)
        return try Data(contentsOf: url)
    }

    // MARK: - Photo Deletion

    override func deletePhoto(_ photo: Photo, fromRequest requestId: String) async throws {
        // Remove from in-memory dict
        allPhotos[requestId]?.removeAll { $0.id == photo.id }

        // Delete local file
        let fileURL = URL(fileURLWithPath: photo.storagePath)
        try? FileManager.default.removeItem(at: fileURL)

        saveToDisk()
    }

    // MARK: - Subscription Tier

    override func updateSubscriptionTier(_ tier: SubscriptionTier) async throws {
        // No-op for local mode
    }

    // MARK: - Persistence

    private var saveURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("local_store.json")
    }

    private struct StorageSnapshot: Codable {
        var requests: [PhotoRequest]
        var photosByRequest: [String: [Photo]]
    }

    private func saveToDisk() {
        let snapshot = StorageSnapshot(requests: requests, photosByRequest: allPhotos)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: saveURL)
        }
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: saveURL),
              let snapshot = try? JSONDecoder().decode(StorageSnapshot.self, from: data) else { return }
        requests = snapshot.requests
        allPhotos = snapshot.photosByRequest
    }

    enum LocalStoreError: LocalizedError {
        case invalidPairingCode
        case requestNotFound

        var errorDescription: String? {
            switch self {
            case .invalidPairingCode: return "Invalid pairing code. Use \"1234\" in demo mode."
            case .requestNotFound: return "Request not found."
            }
        }
    }
}
