import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

/// Phase 1: Firebase-backed store for real cross-device sync.
final class FirebaseFamilyStore: FamilyStore {

    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private var requestsListener: ListenerRegistration?
    private var photosListeners: [String: ListenerRegistration] = [:]

    var authService: AuthService?

    override init() {
        super.init()
        // Restore persisted familyId
        familyId = UserDefaults.standard.string(forKey: "firebase_familyId")
    }

    // MARK: - Family / Pairing

    override func createFamily() async throws -> Family {
        try await authService?.ensureSignedIn()
        guard let uid = authService?.currentUserId else { throw StoreError.notAuthenticated }

        let code = UUID().uuidString
        let now = Date()
        let expiresAt = now.addingTimeInterval(24 * 60 * 60)
        let familyRef = db.collection("families").document()
        let family = Family(
            id: familyRef.documentID,
            createdAt: now,
            createdByUserId: uid,
            pairingCode: code,
            pairingExpiresAt: expiresAt
        )

        try await familyRef.setData([
            "createdAt": Timestamp(date: family.createdAt),
            "createdByUserId": uid,
            "pairingCode": code,
            "pairingExpiresAt": Timestamp(date: expiresAt),
            "subscriptionTier": "free"
        ])

        // Add adult connection
        try await familyRef.collection("connections").document(uid).setData([
            "userId": uid,
            "role": "adult",
            "authProvider": authService?.currentAuthProvider ?? "anonymous",
            "createdAt": Timestamp(date: Date())
        ])

        familyId = family.id
        UserDefaults.standard.set(family.id, forKey: "firebase_familyId")
        return family
    }

    override func joinFamily(pairingCode: String, asRole: String = "grandma") async throws -> Family {
        try await authService?.ensureSignedIn()
        guard let uid = authService?.currentUserId else { throw StoreError.notAuthenticated }

        let snapshot = try await db.collection("families")
            .whereField("pairingCode", isEqualTo: pairingCode)
            .limit(to: 1)
            .getDocuments()

        guard let doc = snapshot.documents.first else {
            throw StoreError.invalidPairingCode
        }

        let data = doc.data()

        // Check expiration
        if let expiresTimestamp = data["pairingExpiresAt"] as? Timestamp,
           expiresTimestamp.dateValue() < Date() {
            throw StoreError.pairingCodeExpired
        }

        let family = Family(
            id: doc.documentID,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            createdByUserId: data["createdByUserId"] as? String ?? "",
            pairingCode: pairingCode,
            pairingExpiresAt: (data["pairingExpiresAt"] as? Timestamp)?.dateValue()
        )

        // Add connection with the specified role
        try await doc.reference.collection("connections").document(uid).setData([
            "userId": uid,
            "role": asRole,
            "authProvider": authService?.currentAuthProvider ?? "anonymous",
            "createdAt": Timestamp(date: Date())
        ])

        familyId = family.id
        UserDefaults.standard.set(family.id, forKey: "firebase_familyId")
        return family
    }

    // MARK: - Requests

    override func createRequest() async throws -> PhotoRequest {
        try await authService?.ensureSignedIn()
        guard let fid = familyId, let uid = authService?.currentUserId else { throw StoreError.notPaired }

        let ref = db.collection("families").document(fid).collection("requests").document()
        let now = Date()

        try await ref.setData([
            "createdAt": Timestamp(date: now),
            "createdByUserId": uid,
            "fromRole": "grandma",
            "status": "pending"
        ])

        return PhotoRequest(
            id: ref.documentID,
            familyId: fid,
            createdAt: now,
            createdByUserId: uid
        )
    }

    override func sendPhotos(imageDataList: [Data]) async throws {
        try await authService?.ensureSignedIn()
        guard let fid = familyId, let uid = authService?.currentUserId else { throw StoreError.notPaired }

        let requestRef = db.collection("families").document(fid).collection("requests").document()
        let now = Date()

        // Create request born as fulfilled
        try await requestRef.setData([
            "createdAt": Timestamp(date: now),
            "createdByUserId": uid,
            "fromRole": "adult",
            "status": "fulfilled",
            "fulfilledAt": Timestamp(date: now),
            "fulfilledByUserId": uid
        ])

        // Upload each photo
        for data in imageDataList {
            let photoId = UUID().uuidString
            let storagePath = "families/\(fid)/requests/\(requestRef.documentID)/\(photoId).jpg"
            let storageRef = storage.reference().child(storagePath)

            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StorageMetadata, Error>) in
                storageRef.putData(data, metadata: metadata) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let result {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: StoreError.notAuthenticated)
                    }
                }
            }

            // Write photo document
            try await requestRef.collection("photos").document(photoId).setData([
                "createdAt": Timestamp(date: Date()),
                "createdByUserId": uid,
                "storagePath": storagePath,
                "status": "active"
            ])
        }
    }

    override func fulfillRequest(_ requestId: String, imageDataList: [Data]) async throws {
        try await authService?.ensureSignedIn()
        guard let fid = familyId, let uid = authService?.currentUserId else { throw StoreError.notPaired }

        let requestRef = db.collection("families").document(fid)
            .collection("requests").document(requestId)

        // Upload each photo
        for data in imageDataList {
            let photoId = UUID().uuidString
            let storagePath = "families/\(fid)/requests/\(requestId)/\(photoId).jpg"
            let storageRef = storage.reference().child(storagePath)

            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StorageMetadata, Error>) in
                storageRef.putData(data, metadata: metadata) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let result {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: StoreError.notAuthenticated)
                    }
                }
            }

            // Write photo document
            try await requestRef.collection("photos").document(photoId).setData([
                "createdAt": Timestamp(date: Date()),
                "createdByUserId": uid,
                "storagePath": storagePath,
                "status": "active"
            ])
        }

        // Mark request fulfilled
        try await requestRef.updateData([
            "status": "fulfilled",
            "fulfilledAt": Timestamp(date: Date()),
            "fulfilledByUserId": uid
        ])
    }

    // MARK: - Photos

    override func loadImageData(for photo: Photo) async throws -> Data? {
        let ref = storage.reference().child(photo.storagePath)
        return try await ref.data(maxSize: 10 * 1024 * 1024)
    }

    // MARK: - Real-time Listeners

    override func startListening() {
        guard let fid = familyId else { return }

        requestsListener = db.collection("families").document(fid)
            .collection("requests")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let docs = snapshot?.documents else { return }

                let parsed = docs.compactMap { doc -> PhotoRequest? in
                    let d = doc.data()
                    return PhotoRequest(
                        id: doc.documentID,
                        familyId: fid,
                        createdAt: (d["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                        createdByUserId: d["createdByUserId"] as? String ?? "",
                        fromRole: d["fromRole"] as? String ?? "grandma",
                        status: PhotoRequest.Status(rawValue: d["status"] as? String ?? "pending") ?? .pending,
                        fulfilledAt: (d["fulfilledAt"] as? Timestamp)?.dateValue(),
                        fulfilledByUserId: d["fulfilledByUserId"] as? String
                    )
                }

                DispatchQueue.main.async {
                    self.requests = parsed
                    for request in parsed where request.status == .fulfilled {
                        self.listenForPhotos(requestId: request.id, familyId: fid)
                    }
                }
            }
    }

    override func stopListening() {
        requestsListener?.remove()
        requestsListener = nil
        photosListeners.values.forEach { $0.remove() }
        photosListeners.removeAll()
    }

    private func listenForPhotos(requestId: String, familyId: String) {
        guard photosListeners[requestId] == nil else { return }

        photosListeners[requestId] = db.collection("families").document(familyId)
            .collection("requests").document(requestId)
            .collection("photos")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let docs = snapshot?.documents else { return }

                let parsed = docs.map { doc -> Photo in
                    let d = doc.data()
                    return Photo(
                        id: doc.documentID,
                        requestId: requestId,
                        createdAt: (d["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                        createdByUserId: d["createdByUserId"] as? String ?? "",
                        storagePath: d["storagePath"] as? String ?? "",
                        isBlocked: d["isBlocked"] as? Bool ?? false,
                        status: d["status"] as? String ?? "active",
                        expiresAt: (d["expiresAt"] as? Timestamp)?.dateValue(),
                        trashedAt: (d["trashedAt"] as? Timestamp)?.dateValue(),
                        purgeAt: (d["purgeAt"] as? Timestamp)?.dateValue()
                    )
                }

                DispatchQueue.main.async {
                    self.allPhotos[requestId] = parsed
                }
            }
    }

    // MARK: - Photo Deletion

    override func deletePhoto(_ photo: Photo, fromRequest requestId: String) async throws {
        guard let fid = familyId else { throw StoreError.notPaired }

        // Delete from Firebase Storage
        let storageRef = storage.reference().child(photo.storagePath)
        try await storageRef.delete()

        // Delete Firestore document
        try await db.collection("families").document(fid)
            .collection("requests").document(requestId)
            .collection("photos").document(photo.id)
            .delete()
    }

    // MARK: - Request Deletion

    override func deleteRequest(_ request: PhotoRequest) async throws {
        guard let fid = familyId else { throw StoreError.notPaired }

        let requestRef = db.collection("families").document(fid)
            .collection("requests").document(request.id)

        // For fulfilled requests, delete all photos from Storage and Firestore first
        if request.status == .fulfilled {
            let photosSnap = try await requestRef.collection("photos").getDocuments()
            for doc in photosSnap.documents {
                if let storagePath = doc.data()["storagePath"] as? String, !storagePath.isEmpty {
                    try? await storage.reference().child(storagePath).delete()
                }
                try await doc.reference.delete()
            }
        }

        try await requestRef.delete()
    }

    // MARK: - Reporting

    override func reportPhoto(_ photo: Photo, fromRequest requestId: String) async throws {
        guard let fid = familyId, let uid = authService?.currentUserId else { throw StoreError.notPaired }

        // Write the report document for admin review
        try await db.collection("families").document(fid)
            .collection("reports")
            .addDocument(data: [
                "photoId": photo.id,
                "requestId": requestId,
                "storagePath": photo.storagePath,
                "reportedByUserId": uid,
                "createdAt": Timestamp(date: Date())
            ])

        // Block the photo immediately so it disappears from all clients via the snapshot listener
        try await db.collection("families").document(fid)
            .collection("requests").document(requestId)
            .collection("photos").document(photo.id)
            .updateData(["isBlocked": true])
    }

    // MARK: - Grandma Action Events

    override func recordFavoriteEvent(photoId: String) async throws {
        guard let fid = familyId else { return }
        try await db.collection("families").document(fid)
            .collection("pendingFavorites")
            .addDocument(data: [
                "photoId": photoId,
                "createdAt": Timestamp(date: Date())
            ])
    }

    override func recordAlbumCreated(albumName: String) async throws {
        guard let fid = familyId else { return }
        try await db.collection("families").document(fid)
            .collection("albumEvents")
            .addDocument(data: [
                "albumName": albumName,
                "createdAt": Timestamp(date: Date())
            ])
    }

    // MARK: - Subscription Tier

    override func updateSubscriptionTier(_ tier: SubscriptionTier) async throws {
        guard let fid = familyId else { throw StoreError.notPaired }

        try await db.collection("families").document(fid).updateData([
            "subscriptionTier": tier.rawValue
        ])
    }

    // MARK: - FCM Token

    override func saveFCMToken(_ token: String) async throws {
        guard let fid = familyId, let uid = authService?.currentUserId else { throw StoreError.notPaired }
        try await db.collection("families").document(fid)
            .collection("connections").document(uid)
            .updateData(["fcmToken": token])
    }

    // MARK: - Photo Restore

    override func restoreTrashedPhotos() async throws {
        guard let fid = familyId else { return }
        let now = Date()
        let requestsSnap = try await db.collection("families").document(fid)
            .collection("requests").getDocuments()
        for requestDoc in requestsSnap.documents {
            let photosSnap = try await db.collection("families").document(fid)
                .collection("requests").document(requestDoc.documentID)
                .collection("photos").whereField("status", isEqualTo: "trashed")
                .getDocuments()
            guard !photosSnap.documents.isEmpty else { continue }
            let batch = db.batch()
            for photoDoc in photosSnap.documents {
                if let purgeAt = (photoDoc.data()["purgeAt"] as? Timestamp)?.dateValue(),
                   purgeAt > now {
                    batch.updateData([
                        "status": "active",
                        "trashedAt": FieldValue.delete(),
                        "purgeAt": FieldValue.delete()
                    ], forDocument: photoDoc.reference)
                }
            }
            try await batch.commit()
        }
    }

    // MARK: - Errors

    enum StoreError: LocalizedError {
        case notAuthenticated
        case invalidPairingCode
        case pairingCodeExpired
        case notPaired

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Not signed in."
            case .invalidPairingCode: return "Invalid pairing code."
            case .pairingCodeExpired: return "This invite link has expired. Ask for a new one."
            case .notPaired: return "Not connected to a family yet."
            }
        }
    }
}
