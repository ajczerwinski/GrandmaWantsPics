import Foundation
import SwiftUI

struct Photo: Identifiable, Codable {
    var id: String
    var requestId: String
    var createdAt: Date
    var createdByUserId: String
    var storagePath: String // local file path (Phase 0) or Firebase Storage path (Phase 1)
    var isBlocked: Bool = false

    // Expiration / soft-delete fields (Phase 1+)
    var status: String = "active"   // "active" | "trashed"
    var expiresAt: Date?
    var trashedAt: Date?
    var purgeAt: Date?               // trashedAt + 30 days

    // Not persisted — loaded at runtime
    var imageData: Data?

    enum CodingKeys: String, CodingKey {
        case id, requestId, createdAt, createdByUserId, storagePath, isBlocked
        case status, expiresAt, trashedAt, purgeAt
    }

    // MARK: - TTL

    static let ttlDays = 30
    static let recoveryDays = 30

    var isTrashed: Bool { status == "trashed" }

    var isRecoverable: Bool {
        guard let purgeAt else { return false }
        return isTrashed && Date() < purgeAt
    }

    // Falls back to createdAt + 30d if expiresAt not set (backward compat for old docs)
    private var effectiveExpiresAt: Date {
        expiresAt ?? Calendar.current.date(byAdding: .day, value: Self.ttlDays, to: createdAt) ?? createdAt
    }

    // Trashed photos are also "expired" so Grandma's gallery hides them automatically
    var isExpired: Bool { isTrashed || Date() >= effectiveExpiresAt }

    // Trashed photos return 0
    var daysUntilExpiry: Int {
        guard !isTrashed else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: effectiveExpiresAt).day ?? 0)
    }

    var daysUntilPurge: Int? {
        guard let purgeAt, isTrashed else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: purgeAt).day ?? 0)
    }
}
