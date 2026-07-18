import Observation
import SwiftUI

enum AppTab: String, Hashable, CaseIterable, Sendable {
    case home
    case dining
    case cafe
    case cart
    case orders
}

enum AppRoute: Hashable {
    case dining(shopID: Int)
    case diningMenu(context: DiningMenuDetailContext)
    case cafe(shopID: Int)
    case menu(shopID: Int, displayID: Int)
    case quickOrder(shopID: Int, displayID: Int)
    case orderConfirmation(isQuickOrder: Bool)
    case settings
}

struct MenuTransitionID: Hashable {
    let shopID: Int
    let displayID: Int
}

struct DiningMenuTransitionID: Hashable {
    let mealID: String
    let courseName: String
    let periodName: String
    let date: Date

    init(context: DiningMenuDetailContext) {
        mealID = context.meal.id
        courseName = context.courseName
        periodName = context.periodName
        date = context.date
    }
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var homePath: [AppRoute] = []
    var diningPath: [AppRoute] = []
    var cafePath: [AppRoute] = []
    var cartPath: [AppRoute] = []
    var ordersPath: [AppRoute] = []

    func binding(for tab: AppTab) -> Binding<[AppRoute]> {
        Binding(
            get: { [weak self] in self?.path(for: tab) ?? [] },
            set: { [weak self] in self?.setPath($0, for: tab) }
        )
    }

    func push(_ route: AppRoute, on tab: AppTab? = nil) {
        let target = tab ?? selectedTab
        var path = path(for: target)
        path.append(route)
        setPath(path, for: target)
    }

    func switchTo(_ tab: AppTab, route: AppRoute? = nil) {
        selectedTab = tab
        if let route { setPath([route], for: tab) }
    }

    func popToRoot(_ tab: AppTab) {
        setPath([], for: tab)
    }

    func reset() {
        AppTab.allCases.forEach { setPath([], for: $0) }
        selectedTab = .home
    }

    @discardableResult
    func handle(url: URL) -> Bool {
        guard url.scheme == "neweligaorder" else { return false }
        let destination = url.host ?? url.pathComponents.dropFirst().first ?? ""
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let shopID = components?.queryItems?.first(where: { $0.name == "shopID" })?.value.flatMap(Int.init)
        let displayID = components?.queryItems?.first(where: { $0.name == "displayID" })?.value.flatMap(Int.init)

        if destination == "menu", let shopID, let displayID {
            switchTo(.cafe, route: .menu(shopID: shopID, displayID: displayID))
            return true
        }
        if destination == "quick-order", let shopID, let displayID {
            switchTo(.cafe, route: .quickOrder(shopID: shopID, displayID: displayID))
            return true
        }
        guard let tab = AppTab(rawValue: destination) else { return false }
        switchTo(tab)
        return true
    }

    private func path(for tab: AppTab) -> [AppRoute] {
        switch tab {
        case .home: homePath
        case .dining: diningPath
        case .cafe: cafePath
        case .cart: cartPath
        case .orders: ordersPath
        }
    }

    private func setPath(_ path: [AppRoute], for tab: AppTab) {
        switch tab {
        case .home: homePath = path
        case .dining: diningPath = path
        case .cafe: cafePath = path
        case .cart: cartPath = path
        case .orders: ordersPath = path
        }
    }
}
