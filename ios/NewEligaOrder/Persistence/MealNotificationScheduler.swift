import CryptoKit
import Foundation
import FoundationModels
import UserNotifications

struct MealNotificationCopy: Codable, Equatable, Sendable {
    let title: String
    let body: String
}

struct MealNotificationCandidate: Equatable, Sendable {
    let meal: MealNotificationScheduler.Meal
    let menuName: String
    let reason: String?
    let otherMenuNames: [String]
}

enum MealNotificationPolicy {
    static func candidate(
        for meal: MealNotificationScheduler.Meal,
        in preparedDay: PreparedDiningDay
    ) -> MealNotificationCandidate? {
        let matchingPeriods = preparedDay.periods.filter { meal.matches(periodName: $0.time) }
        let allMenuNames = matchingPeriods
            .flatMap(\.courses)
            .flatMap(\.menus)
            .map { $0.titlePresentation.displayName }

        for period in matchingPeriods {
            for course in period.courses where !course.isSoldOut {
                for menu in course.menus where !menu.isSoldOut {
                    let key = DiningPreparationKey.make(period: period, course: course, meal: menu)
                    guard preparedDay.preparations[key]?.personalization.recommendation == .recommended else {
                        continue
                    }
                    let menuName = menu.titlePresentation.displayName
                    return MealNotificationCandidate(
                        meal: meal,
                        menuName: menuName,
                        reason: preparedDay.preparations[key]?.personalization.reason,
                        otherMenuNames: allMenuNames.filter { $0 != menuName }
                    )
                }
            }
        }
        return nil
    }

    static func fallbackCopy(for candidate: MealNotificationCandidate) -> MealNotificationCopy {
        let reason = cleaned(candidate.reason ?? "", maximumLength: 60)
        let body = reason.isEmpty
            ? "오늘 \(candidate.meal.displayName)은 이 메뉴를 추천해요."
            : "\(reason). 오늘 \(candidate.meal.displayName)은 이 메뉴를 추천해요."
        return MealNotificationCopy(
            title: "✨ \(candidate.menuName) 추천",
            body: body
        )
    }

    static func validated(
        _ copy: MealNotificationCopy,
        for candidate: MealNotificationCandidate
    ) -> MealNotificationCopy? {
        let title = cleaned(copy.title, maximumLength: 48)
        let body = cleaned(copy.body, maximumLength: 120)
        guard !title.isEmpty, !body.isEmpty, title.localizedCaseInsensitiveContains(candidate.menuName) else {
            return nil
        }
        let combined = "\(title) \(body)"
        guard !candidate.otherMenuNames.contains(where: {
            !$0.isEmpty && combined.localizedCaseInsensitiveContains($0)
        }) else { return nil }

        return MealNotificationCopy(
            title: title.hasPrefix("✨") ? title : "✨ \(title)",
            body: body
        )
    }

    private static func cleaned(_ value: String, maximumLength: Int) -> String {
        let normalized = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(normalized.prefix(maximumLength))
    }
}

actor MealNotificationCopyGenerator {
    static let shared = MealNotificationCopyGenerator()

    static let instructions = """
        엘리가오더의 식사 추천 로컬 알림 문구를 짧고 자연스러운 한국어로 작성한다.
        제공된 추천 메뉴 정확히 하나만 언급하고, 다른 메뉴나 음식 또는 사실을 만들지 않는다.
        title에는 제공된 메뉴명을 원문 그대로 반드시 포함한다. title은 32자, body는 80자 이내로 쓴다.
        과장, 건강 효능, 이모지 도배, 마크다운, 줄바꿈은 사용하지 않는다.
        """

    private let defaults: UserDefaults
    private let cacheKey = "meal-notification-copy-v1"
    private var cache: [String: MealNotificationCopy]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: cacheKey),
           let decoded = try? JSONDecoder().decode([String: MealNotificationCopy].self, from: data) {
            cache = decoded
        } else {
            cache = [:]
        }
    }

    func copy(for candidate: MealNotificationCandidate) async -> MealNotificationCopy {
        let key = candidateKey(candidate)
        if let cached = cache[key],
           let validated = MealNotificationPolicy.validated(cached, for: candidate) {
            return validated
        }

        let fallback = MealNotificationPolicy.fallbackCopy(for: candidate)
        guard #available(iOS 26.0, *), FoundationModelRuntimePolicy.isEnabled,
              let generated = await OnDeviceMealNotificationWriter.shared.copy(for: candidate),
              let validated = MealNotificationPolicy.validated(generated, for: candidate)
        else { return fallback }

        cache[key] = validated
        trimCacheIfNeeded()
        if let data = try? JSONEncoder().encode(cache) {
            defaults.set(data, forKey: cacheKey)
        }
        return validated
    }

    private func candidateKey(_ candidate: MealNotificationCandidate) -> String {
        let source = "\(candidate.meal.rawValue)|\(candidate.menuName)|\(candidate.reason ?? "")"
        let digest = SHA256.hash(data: Data(source.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func trimCacheIfNeeded() {
        guard cache.count > 96 else { return }
        for key in cache.keys.prefix(cache.count - 72) {
            cache.removeValue(forKey: key)
        }
    }
}

@available(iOS 26.0, *)
@Generable(description: "추천 메뉴 하나만 강조하는 짧은 한국어 로컬 알림 문구")
private struct GeneratedMealNotificationCopy: Sendable {
    @Guide(description: "추천 메뉴명을 원문 그대로 포함한 32자 이내 제목")
    var title: String

    @Guide(description: "다른 메뉴를 언급하지 않는 80자 이내 본문")
    var body: String
}

@available(iOS 26.0, *)
private actor OnDeviceMealNotificationWriter {
    static let shared = OnDeviceMealNotificationWriter()

    func copy(for candidate: MealNotificationCandidate) async -> MealNotificationCopy? {
        let model = SystemLanguageModel.default
        guard model.isAvailable, model.supportsLocale(Locale(identifier: "ko_KR")) else { return nil }
        let prompt = """
            <식사구분>\(candidate.meal.displayName)</식사구분>
            <추천메뉴>\(String(candidate.menuName.prefix(100)))</추천메뉴>
            <추천근거>\(String((candidate.reason ?? "정보 없음").prefix(100)))</추천근거>
            """

        return try? await FoundationModelRequestCoordinator.shared.perform {
            let session = LanguageModelSession(
                model: model,
                instructions: MealNotificationCopyGenerator.instructions
            )
            do {
                let response = try await session.respond(
                    to: prompt,
                    generating: GeneratedMealNotificationCopy.self
                )
                return MealNotificationCopy(title: response.content.title, body: response.content.body)
            } catch {
                return nil
            }
        }
    }
}

struct MealNotificationScheduler: Sendable {
    enum Meal: String, CaseIterable, Codable, Sendable {
        case lunch
        case dinner

        var legacyIdentifier: String { "eliga.meal.\(rawValue)" }
        var identifierPrefix: String { "\(legacyIdentifier).day." }
        var displayName: String { self == .lunch ? "중식" : "석식" }
        var title: String { self == .lunch ? "점심 식단을 확인해 보세요" : "저녁 식단을 확인해 보세요" }
        var body: String { self == .lunch ? "오늘의 점심 메뉴가 준비되어 있습니다." : "오늘의 저녁 메뉴를 확인할 시간입니다." }

        func matches(periodName: String) -> Bool {
            let normalized = periodName
                .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
                .lowercased()
            return switch self {
            case .lunch: normalized.contains("중식") || normalized.contains("점심") || normalized.contains("lunch")
            case .dinner: normalized.contains("석식") || normalized.contains("저녁") || normalized.contains("dinner")
            }
        }
    }

    private static let rollingDayCount = 14

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// 반복 알림의 문구가 다음 날에도 남지 않도록 날짜별 요청을 2주치 예약한다.
    func schedule(_ meal: Meal, at time: Date, enabled: Bool, now: Date = .now) async throws {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter {
            $0 == meal.legacyIdentifier || $0.hasPrefix(meal.identifierPrefix)
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        guard enabled else { return }

        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: now)
        for offset in 0..<Self.rollingDayCount {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let scheduledDate = scheduledDate(on: day, using: time, calendar: calendar),
                  scheduledDate > now
            else { continue }
            try await addRequest(
                meal: meal,
                date: scheduledDate,
                copy: MealNotificationCopy(title: meal.title, body: meal.body),
                isPersonalized: false,
                menuName: nil,
                center: center,
                calendar: calendar
            )
        }
    }

    func refreshRollingSchedules(preferences: PreferencesStore, now: Date = .now) async throws {
        try await schedule(
            .lunch,
            at: preferences.lunchTime,
            enabled: preferences.lunchNotificationEnabled,
            now: now
        )
        try await schedule(
            .dinner,
            at: preferences.dinnerTime,
            enabled: preferences.dinnerNotificationEnabled,
            now: now
        )
    }

    /// 이미 계산된 오늘/내일 추천만 사용해 아직 울리지 않은 일반 알림을 교체한다.
    func personalize(
        date: Date,
        preparedDay: PreparedDiningDay,
        preferences: PreferencesStore,
        now: Date = .now
    ) async throws {
        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.autoupdatingCurrent

        for meal in Meal.allCases {
            let enabled = meal == .lunch
                ? preferences.lunchNotificationEnabled
                : preferences.dinnerNotificationEnabled
            guard enabled else { continue }
            let time = meal == .lunch ? preferences.lunchTime : preferences.dinnerTime
            guard let scheduledDate = scheduledDate(on: date, using: time, calendar: calendar),
                  scheduledDate > now,
                  let candidate = MealNotificationPolicy.candidate(for: meal, in: preparedDay)
            else { continue }

            let copy = await MealNotificationCopyGenerator.shared.copy(for: candidate)
            try await addRequest(
                meal: meal,
                date: scheduledDate,
                copy: copy,
                isPersonalized: true,
                menuName: candidate.menuName,
                center: center,
                calendar: calendar
            )
        }
    }

    private func scheduledDate(on day: Date, using time: Date, calendar: Calendar) -> Date? {
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(
            bySettingHour: timeComponents.hour ?? 0,
            minute: timeComponents.minute ?? 0,
            second: 0,
            of: day
        )
    }

    private func addRequest(
        meal: Meal,
        date: Date,
        copy: MealNotificationCopy,
        isPersonalized: Bool,
        menuName: String?,
        center: UNUserNotificationCenter,
        calendar: Calendar
    ) async throws {
        let identifier = identifier(for: meal, date: date, calendar: calendar)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = copy.title
        content.body = copy.body
        content.sound = .default
        content.threadIdentifier = "eliga.meal.\(meal.rawValue)"
        content.userInfo = [
            "meal": meal.rawValue,
            "date": dayIdentifier(for: date, calendar: calendar),
            "personalized": isPersonalized,
            "menuName": menuName ?? "",
        ]

        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    private func identifier(for meal: Meal, date: Date, calendar: Calendar) -> String {
        "\(meal.identifierPrefix)\(dayIdentifier(for: date, calendar: calendar))"
    }

    private func dayIdentifier(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
