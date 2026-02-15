import Foundation

struct PhotoRequest: Identifiable, Codable {
    var id: String
    var familyId: String
    var createdAt: Date
    var createdByUserId: String
    var fromRole: String = "grandma"
    var status: Status = .pending
    var fulfilledAt: Date?
    var fulfilledByUserId: String?

    enum Status: String, Codable {
        case pending
        case fulfilled
    }
}
