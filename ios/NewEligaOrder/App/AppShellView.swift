import SwiftUI

struct AppShellView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(NetworkMonitor.self) private var network
    @Environment(AppIntentHandoff.self) private var intentHandoff
    @SceneStorage("navigation.selectedTab") private var restoredTab = AppTab.home.rawValue
    @Namespace private var menuTransitionNamespace
    @State private var isCafeSearchPresented = false

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            Tab("홈", systemImage: "house", value: AppTab.home) {
                NavigationStack(path: router.binding(for: .home)) {
                    HomeView()
                        .withAppDestinations(menuTransitionNamespace: menuTransitionNamespace)
                }
            }

            Tab("식단", systemImage: "fork.knife", value: AppTab.dining) {
                NavigationStack(path: router.binding(for: .dining)) {
                    DiningView(shopID: store.diningShopID, transitionNamespace: menuTransitionNamespace)
                        .withAppDestinations(menuTransitionNamespace: menuTransitionNamespace)
                }
            }

            Tab("카페", systemImage: "cup.and.saucer", value: AppTab.cafe) {
                NavigationStack(path: router.binding(for: .cafe)) {
                    CafeView(
                        initialShopID: store.selectedShopID,
                        transitionNamespace: menuTransitionNamespace,
                        isSearchPresented: $isCafeSearchPresented
                    )
                        .withAppDestinations(menuTransitionNamespace: menuTransitionNamespace)
                }
            }

            Tab("장바구니", systemImage: "bag", value: AppTab.cart) {
                NavigationStack(path: router.binding(for: .cart)) {
                    CartView()
                        .withAppDestinations(menuTransitionNamespace: menuTransitionNamespace)
                }
            }
            .badge(store.totalCartCount)

            Tab("내역", systemImage: "receipt", value: AppTab.orders) {
                NavigationStack(path: router.binding(for: .orders)) {
                    OrdersView()
                        .withAppDestinations(menuTransitionNamespace: menuTransitionNamespace)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .appTabBarBehavior()
        .appCafeBottomAccessory(
            isEnabled: router.selectedTab == .cafe && router.cafePath.isEmpty && !isCafeSearchPresented,
            shops: store.cafeShops,
            selectedShopID: store.selectedShopID ?? store.cafeShops.first?.id ?? 5,
            selectShop: { store.selectShop($0) }
        ) {
            isCafeSearchPresented = true
        }
        .safeAreaInset(edge: .top) {
            if !network.isConnected {
                NetworkStatusBanner()
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: network.isConnected)
        .onAppear {
            if let tab = AppTab(rawValue: restoredTab) {
                router.selectedTab = tab
            }
            consumeIntentHandoff()
        }
        .onChange(of: router.selectedTab) { _, tab in
            restoredTab = tab.rawValue
            if tab != .cafe {
                isCafeSearchPresented = false
            }
        }
        .onChange(of: intentHandoff.pendingDestination) { _, _ in
            consumeIntentHandoff()
        }
        .alert(
            "새로고침하지 못했습니다",
            isPresented: Binding(
                get: { store.globalError != nil },
                set: { if !$0 { store.globalError = nil } }
            )
        ) {
            Button("다시 시도") { Task { try? await store.bootstrap() } }
            Button("확인", role: .cancel) { store.globalError = nil }
        } message: {
            Text(store.globalError ?? "잠시 후 다시 시도해 주세요.")
        }
    }

    private func consumeIntentHandoff() {
        guard let destination = intentHandoff.consume() else { return }
        switch destination {
        case .tab(let tab):
            router.switchTo(tab)
        case .cafeMenu(let shopID, let displayID):
            store.selectShop(shopID)
            router.switchTo(.cafe, route: .menu(shopID: shopID, displayID: displayID))
        case .dining(let shopID):
            router.switchTo(.dining, route: .dining(shopID: shopID))
        case .diningMeal(let id):
            guard let record = AppIntentEntityRepository.diningRecords().first(where: { $0.id == id }) else {
                router.switchTo(.dining)
                return
            }
            router.switchTo(.dining, route: .diningMenu(context: record.detailContext))
        }
    }
}

private extension View {
    func withAppDestinations(menuTransitionNamespace: Namespace.ID) -> some View {
        navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .dining(let shopID):
                DiningView(shopID: shopID, transitionNamespace: menuTransitionNamespace)
            case .diningMenu(let context):
                DiningMenuDetailView(context: context, transitionNamespace: menuTransitionNamespace)
            case .cafe(let shopID):
                CafeView(initialShopID: shopID, transitionNamespace: menuTransitionNamespace)
            case .menu(let shopID, let displayID):
                MenuDetailView(shopID: shopID, displayID: displayID, transitionNamespace: menuTransitionNamespace)
            case .quickOrder(let shopID, let displayID):
                QuickOrderLaunchView(shopID: shopID, displayID: displayID)
            case .orderConfirmation(let shopID, let isQuickOrder):
                OrderConfirmationView(shopID: shopID, isQuickOrder: isQuickOrder)
            case .settings:
                SettingsView()
            }
        }
    }
}
