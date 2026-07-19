import ActivityKit
import Foundation

enum OrderActivityPhase: String, Codable, Hashable, Sendable {
    case submitted
    case preparing
    case ready
    case completed
    case cancelled

    init(statusCode: String) {
        switch statusCode.uppercased() {
        case "ORDER_RECEPTION", "ORDER_RECEIVED", "ORDER_ACCEPTED": self = .submitted
        case "WAITING_FOR_PICKUP", "PICKUP_READY", "READY": self = .ready
        case "PICKUP_COMPLETE", "ORDER_COMPLETE", "COMPLETED": self = .completed
        case "ORDER_CANCEL", "ORDER_CANCELED", "ORDER_CANCELLED", "CANCELLED": self = .cancelled
        default: self = .preparing
        }
    }

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
