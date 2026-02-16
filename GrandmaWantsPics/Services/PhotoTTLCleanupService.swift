import Foundation

/// Client-side cleanup of expired photos for free-tier families.
///
/// TODO: Migrate this to a Firebase Cloud Function for reliability.
/// Client-side cleanup only runs when the app launches, so photos may linger
/// past their TTL if the app isn't opened. A Cloud Function running on a
/// schedule (e.g., daily) would ensure timely deletion regardless of app usage.
struct PhotoTTLCleanupService {

    let store: FamilyStore

    func deleteExpiredPhotos() async {
        for (requestId, photos) in store.allPhotos {
            for photo in photos where photo.isExpired {
                do {
                    try await store.deletePhoto(photo, fromRequest: requestId)
                } catch {
                    print("Failed to delete expired photo \(photo.id): \(error)")
                }
            }
        }
    }
}
