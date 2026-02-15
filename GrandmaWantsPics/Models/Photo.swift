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
}
