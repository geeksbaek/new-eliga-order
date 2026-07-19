import SwiftUI

@main
struct NewEligaOrderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = AppStore()
    @State private var router = AppRouter()
    @State private var network = NetworkMonitor()
    @State private var intentHandoff = AppIntentHandoff.shared

    var body: some Scene {
        WindowGroup {
            Group {
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-ui-testing-cafe-sections") {
                    CafePrioritySectionsFixtureView()
                } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-cafe-menu-detail-quantity") {
                    CafeMenuDetailQuantityFixtureView()
                } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-cafe-menu-detail-holiday") {
                    CafeMenuDetailHolidayFixtureView()
                } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-cafe-holiday") {
                    CafeHolidayFixtureView()
                } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-shop-picker") {
                    CafeShopPickerFixtureView()
                } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-cafe-thumb-switcher") {
                    CafeShopThumbSwitcherFixtureView()
                } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-dining-detail") {
                    DiningMenuDetailFixtureView()
                } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-dining-personalization") {
                    DiningPersonalizationFixtureView()
                } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-settings") {
                    NavigationStack { SettingsView() }
                } else {
                    authenticatedRoot
                }
#else
                authenticatedRoot
#endif
            }
            .environment(store)
            .environment(router)
            .environment(network)
            .environment(intentHandoff)
            .tint(AppPalette.brand)
            .task(id: store.authenticationState) {
                guard store.authenticationState == .authenticated else { return }
                if store.shops.isEmpty {
                    try? await store.bootstrap()
                }
                await store.preloadPrimaryContent()
                OrderMonitoringCoordinator.shared.applicationDidBecomeActive(using: store.api)
            }
            .onOpenURL { _ = router.handle(url: $0) }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active where store.authenticationState == .authenticated:
                    OrderMonitoringCoordinator.shared.applicationDidBecomeActive(using: store.api)
                    Task {
                        await store.refreshCafeMetadata()
                        await WidgetSnapshotSync.refresh(using: store)
                        await OrderMonitoringCoordinator.shared.refreshOnce(using: store.api)
                    }
                case .background where store.authenticationState == .authenticated:
                    OrderMonitoringCoordinator.shared.applicationDidEnterBackground(using: store.api)
                default:
                    break
                }
            }
        }
    }

    @ViewBuilder
    private var authenticatedRoot: some View {
        Group {
                switch store.authenticationState {
                case .signedOut, .authenticating:
                    LoginView()
                case .authenticated:
                    AppShellView()
                }
        }
    }
}
