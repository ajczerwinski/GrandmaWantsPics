import Foundation

struct Family: Identifiable, Codable {
    var id: String
    var createdAt: Date
    var createdByUserId: String
    var pairingCode: String
}
