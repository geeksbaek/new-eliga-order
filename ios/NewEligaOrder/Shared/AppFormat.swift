import Foundation

@MainActor
enum AppFormat {
    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "KRW"
        formatter.currencySymbol = "₩"
        formatter.maximumFractionDigits = 0
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter
    }()

    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let orderDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 EEEE"
        return formatter
    }()

    private static let orderTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h:mm"
        return formatter
    }()

    private static let isoDateTimeFormatter = ISO8601DateFormatter()

    private static let fractionalISODateTimeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let serverDateTimeFormatters: [DateFormatter] = [
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd'T'HH:mm",
    ].map { format in
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }

    static func won(_ amount: Int) -> String {
        currency.string(from: NSNumber(value: max(0, amount))) ?? "₩\(amount)"
    }

    static func apiDate(_ date: Date) -> String { apiDateFormatter.string(from: date) }

    static func orderDate(_ raw: String) -> Date? {
        fractionalISODateTimeFormatter.date(from: raw)
            ?? isoDateTimeFormatter.date(from: raw)
            ?? serverDateTimeFormatters.lazy.compactMap { $0.date(from: raw) }.first
    }

    static func orderDayKey(_ raw: String) -> String {
        guard let date = orderDate(raw) else { return raw.isEmpty ? "unknown" : raw }
        return apiDateFormatter.string(from: date)
    }

    static func orderDayTitle(_ raw: String) -> String {
        guard let date = orderDate(raw) else { return "날짜 확인 필요" }
        let dateText = orderDayFormatter.string(from: date)
        if Calendar.current.isDateInToday(date) { return "오늘 · \(dateText)" }
        if Calendar.current.isDateInYesterday(date) { return "어제 · \(dateText)" }
        return dateText
    }

    static func orderTime(_ raw: String) -> String {
        guard let date = orderDate(raw) else { return raw.isEmpty ? "시간 미상" : minutePrecision(raw) }
        return orderTimeFormatter.string(from: date)
    }

    /// API가 `HH:mm:ss`로 내려주더라도 사용자에게는 분 단위까지만 표시한다.
    nonisolated static func minutePrecision(_ raw: String) -> String {
        raw.replacingOccurrences(
            of: #"(?<!\d)([01]?\d|2[0-3]):([0-5]\d):[0-5]\d(?:\.\d+)?(?!\d)"#,
            with: "$1:$2",
            options: .regularExpression
        )
    }

    nonisolated static func timeRange(start: String?, end: String?) -> String {
        let values = [start, end]
            .compactMap { $0 }
            .map(minutePrecision)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.joined(separator: "–")
    }

    static func orderStatus(_ status: String) -> String {
        switch status {
        case "ORDER_RECEPTION": "접수"
        case "WAITING_FOR_PICKUP": "픽업 대기"
        case "PICKUP_COMPLETE", "ORDER_COMPLETE": "완료"
        case "ORDER_CANCEL", "ORDER_CANCELED", "ORDER_CANCELLED": "취소"
        default: status.isEmpty ? "알 수 없음" : status
        }
    }

    static func congestion(_ value: String?) -> String {
        switch value {
        case "SMOOTH": "여유"
        case "NORMAL": "보통"
        case "CROWDED": "혼잡"
        default: value ?? ""
        }
    }
}
