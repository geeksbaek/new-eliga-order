import ActivityKit
import Foundation

enum OrderActivityPhase: String, Codable, Hashable, Sendable {
    case submitted
    case preparing
    case ready
    case completed
    case cancelled

    var isTerminal: Bool { self == .completed || self == .cancelled }
}

struct OrderActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        let phase: OrderActivityPhase
        let statusText: String
        let orderNumber: String
        let updatedAt: Date
    }

    let orderID: Int
    let shopName: String
    let itemSummary: String
    let total: Int
}
