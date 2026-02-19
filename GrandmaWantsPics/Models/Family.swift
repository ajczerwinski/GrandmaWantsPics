import Foundation

struct Family: Identifiable, Codable {
    var id: String
    var createdAt: Date
    var createdByUserId: String
    var pairingCode: String
    var pairingExpiresAt: Date?
    var subscriptionTier: SubscriptionTier

    init(id: String, createdAt: Date, createdByUserId: String, pairingCode: String, pairingExpiresAt: Date? = nil, subscriptionTier: SubscriptionTier = .free) {
        self.id = id
        self.createdAt = createdAt
        self.createdByUserId = createdByUserId
        self.pairingCode = pairingCode
        self.pairingExpiresAt = pairingExpiresAt
        self.subscriptionTier = subscriptionTier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        createdByUserId = try container.decode(String.self, forKey: .createdByUserId)
        pairingCode = try container.decode(String.self, forKey: .pairingCode)
        pairingExpiresAt = try container.decodeIfPresent(Date.self, forKey: .pairingExpiresAt)
        subscriptionTier = try container.decodeIfPresent(SubscriptionTier.self, forKey: .subscriptionTier) ?? .free
    }
}
