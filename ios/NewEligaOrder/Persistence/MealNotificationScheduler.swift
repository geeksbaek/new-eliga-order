import Foundation
import UserNotifications

struct MealNotificationScheduler: Sendable {
    enum Meal: String, CaseIterable, Sendable {
        case lunch
        case dinner

        var identifier: String { "eliga.meal.\(rawValue)" }
        var title: String { self == .lunch ? "점심 식단을 확인해 보세요" : "저녁 식단을 확인해 보세요" }
        var body: String { self == .lunch ? "오늘의 점심 메뉴가 준비되어 있습니다." : "오늘의 저녁 메뉴를 확인할 시간입니다." }
    }

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    func schedule(_ meal: Meal, at date: Date, enabled: Bool) async throws {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [meal.identifier])
        guard enabled else { return }

        let content = UNMutableNotificationContent()
        content.title = meal.title
        content.body = meal.body
        content.sound = .default
        var components = Calendar.current.dateComponents([.hour, .minute], from: date)
        components.calendar = .current
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        try await center.add(UNNotificationRequest(identifier: meal.identifier, content: content, trigger: trigger))
    }
}
