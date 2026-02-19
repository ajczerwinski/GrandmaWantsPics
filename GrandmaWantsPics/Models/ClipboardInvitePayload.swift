import Foundation

struct ClipboardInvitePayload: Codable {
    let app: String
    let code: String
    let role: String
    let ts: Int
}
