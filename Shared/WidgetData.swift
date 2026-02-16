import Foundation

struct WidgetData: Codable {
    /// Which role the user selected ("grandma" or "adult"), or nil if not yet chosen
    var role: String?

    /// Whether the user has paired with a family
    var isPaired: Bool

    /// For Adult: count of pending requests
    var pendingRequestCount: Int

    /// For Adult: date of the oldest pending (unfulfilled) request
    var oldestPendingRequestDate: Date?

    /// For Adult: date the adult last fulfilled a request
    var lastFulfilledDate: Date?

    /// For Grandma: date grandma last received photos (most recent fulfilledAt)
    var lastPhotosReceivedDate: Date?

    /// For Grandma: date grandma last sent a request
    var lastRequestSentDate: Date?

    /// Timestamp when this data was last written
    var updatedAt: Date

    static let empty = WidgetData(
        role: nil,
        isPaired: false,
        pendingRequestCount: 0,
        oldestPendingRequestDate: nil,
        lastFulfilledDate: nil,
        lastPhotosReceivedDate: nil,
        lastRequestSentDate: nil,
        updatedAt: Date()
    )
}
