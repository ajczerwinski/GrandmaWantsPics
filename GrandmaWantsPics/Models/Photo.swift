import Foundation
import SwiftUI

struct Photo: Identifiable, Codable {
    var id: String
    var requestId: String
    var createdAt: Date
    var createdByUserId: String
    var storagePath: String // local file path (Phase 0) or Firebase Storage path (Phase 1)

    // Not persisted — loaded at runtime
    var imageData: Data?

    enum CodingKeys: String, CodingKey {
        case id, requestId, createdAt, createdByUserId, storagePath
    }

    // MARK: - TTL

    static let ttlDays = 30

    var expiresAt: Date {
        Calendar.current.date(byAdding: .day, value: Self.ttlDays, to: createdAt) ?? createdAt
    }

    var isExpired: Bool {
        Date() >= expiresAt
    }

    var daysUntilExpiry: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day ?? 0)
    }
}
