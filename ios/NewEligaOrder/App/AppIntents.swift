import AppIntents
import Observation

enum AppIntentDestination: Equatable, Sendable {
    case tab(AppTab)
    case cafeMenu(shopID: Int, displayID: Int)
    case dining(shopID: Int)
    case diningMeal(id: String)
}

@MainActor
@Observable
final class AppIntentHandoff {
    static let shared = AppIntentHandoff()
    private(set) var pendingDestination: AppIntentDestination?

    private init() {}

    func request(_ destination: AppIntentDestination) {
        pendingDestination = destination
    }

    func consume() -> AppIntentDestination? {
        defer { pendingDestination = nil }
        return pendingDestination
    }
}

struct OpenTodayDiningIntent: AppIntent {
    static let title: LocalizedStringResource = "오늘 식단 열기"
    static let description = IntentDescription("엘리가오더에서 오늘의 사내 식단을 엽니다.")

    @available(iOS, introduced: 18.0, deprecated: 26.0)
    static var openAppWhenRun: Bool { true }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { [.foreground(.immediate)] }

    func perform() async throws -> some IntentResult {
        await AppIntentHandoff.shared.request(.tab(.dining))
        return .result()
    }
}

struct OpenCafeIntent: AppIntent {
    static let title: LocalizedStringResource = "카페 메뉴 열기"
    static let description = IntentDescription("엘리가오더의 카페 메뉴와 검색을 엽니다.")

    @available(iOS, introduced: 18.0, deprecated: 26.0)
    static var openAppWhenRun: Bool { true }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { [.foreground(.immediate)] }

    func perform() async throws -> some IntentResult {
        await AppIntentHandoff.shared.request(.tab(.cafe))
        return .result()
    }
}

struct OpenCafeMenuIntent: OpenIntent {
    static let title: LocalizedStringResource = "카페 메뉴 보기"
    static let description = IntentDescription("선택한 카페 메뉴의 상세 화면을 엽니다.")

    @Parameter(title: "메뉴", requestValueDialog: "어떤 메뉴를 볼까요?")
    var target: CafeMenuEntity

    func perform() async throws -> some IntentResult {
        await AppIntentHandoff.shared.request(
            .cafeMenu(shopID: target.shopID, displayID: target.displayID)
        )
        return .result()
    }
}

struct OpenDiningMealIntent: OpenIntent {
    static let title: LocalizedStringResource = "오늘 식사 보기"
    static let description = IntentDescription("선택한 오늘의 식사가 있는 식단 화면을 엽니다.")

    @Parameter(title: "식사", requestValueDialog: "어떤 식사를 볼까요?")
    var target: DiningMealEntity

    func perform() async throws -> some IntentResult {
        await AppIntentHandoff.shared.request(.diningMeal(id: target.id))
        return .result()
    }
}

struct NewEligaOrderShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenTodayDiningIntent(),
            phrases: [
                "\(.applicationName)에서 오늘 식단 보기",
                "\(.applicationName)에서 점심 메뉴 보기",
            ],
            shortTitle: "오늘 식단",
            systemImageName: "fork.knife"
        )

        AppShortcut(
            intent: OpenCafeIntent(),
            phrases: [
                "\(.applicationName)에서 카페 메뉴 보기",
                "\(.applicationName)에서 음료 찾기",
            ],
            shortTitle: "카페 메뉴",
            systemImageName: "cup.and.saucer.fill"
        )

        AppShortcut(
            intent: OpenCafeMenuIntent(),
            phrases: [
                "\(.applicationName)에서 \(\.$target) 보기",
                "\(.applicationName)에서 \(\.$target) 메뉴 열기",
            ],
            shortTitle: "메뉴 찾기",
            systemImageName: "magnifyingglass"
        )

        AppShortcut(
            intent: OpenDiningMealIntent(),
            phrases: [
                "\(.applicationName)에서 \(\.$target) 식사 보기",
            ],
            shortTitle: "식사 찾기",
            systemImageName: "takeoutbag.and.cup.and.straw.fill"
        )
    }
}
