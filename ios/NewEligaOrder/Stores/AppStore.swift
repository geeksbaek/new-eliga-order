import Foundation
import Observation

enum AuthenticationState: Equatable {
    case signedOut
    case authenticating
    case authenticated
}

@MainActor
@Observable
final class AppStore {
    let api: EligaAPI
    private var preferences: PreferencesStore
    private var lastMetadataRefreshAt: Date?

    private(set) var authenticationState: AuthenticationState
    private(set) var shops: [Shop] = []
    private(set) var cartsByShop: [Int: Cart] = [:]
    private(set) var cafePlansByShop: [Int: CafeSalesPlan?] = [:]
    private(set) var favorites: Set<FavoriteMenu>
    private(set) var diningPreferences: [String]
    private(set) var isBootstrapping = false
    private(set) var quickOrderSession: QuickOrderSession?
    var selectedShopID: Int?
    var globalError: String?
    var userIDHint: String

    init(api: EligaAPI = EligaAPI(), preferences: PreferencesStore = PreferencesStore()) {
        self.api = api
        self.preferences = preferences
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-auth") {
            api.client.signOut()
        }
        self.authenticationState = api.client.isAuthenticated ? .authenticated : .signedOut
        self.userIDHint = preferences.rememberedUserID
        self.selectedShopID = preferences.lastShopID
        self.favorites = preferences.favorites
        self.diningPreferences = preferences.diningPreferences
        api.client.onAuthenticationExpired = { [weak self] in
            self?.handleExpiredAuthentication()
        }
    }

    var selectedShop: Shop? { shops.first { $0.id == selectedShopID } }
    var diningShopID: Int { shops.first { $0.kind == .cafeteria || $0.kind == .restaurant }?.id ?? 7 }
    var cafeShops: [Shop] { shops.filter(\.canOrder) }
    var totalCartCount: Int { cartsByShop.values.reduce(0) { $0 + $1.itemCount } }

    func cart(for shopID: Int?) -> Cart {
        guard let shopID else { return .empty }
        return cartsByShop[shopID] ?? Cart(id: nil, shopID: shopID, items: [])
    }

    func login(userID: String, password: String) async throws {
        let trimmed = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !password.isEmpty else { throw LoginValidationError.missingCredentials }
        authenticationState = .authenticating
        PushNotificationCoordinator.prepareForAuthentication()
        do {
            try await api.client.signIn(userID: trimmed, password: password)
            userIDHint = trimmed
            preferences.rememberedUserID = trimmed
            authenticationState = .authenticated
        } catch {
            authenticationState = .signedOut
            throw error
        }

        do {
            try await bootstrap()
        } catch is CancellationError {
            return
        } catch {
            globalError = error.localizedDescription
        }
    }

    func logout() {
        api.client.signOut()
        globalError = nil
        clearAuthenticatedState()
    }

    private func handleExpiredAuthentication() {
        clearAuthenticatedState()
        globalError = "로그인 세션이 만료되었습니다. 다시 로그인해 주세요."
    }

    private func clearAuthenticatedState() {
        PushNotificationCoordinator.didSignOut()
        OrderMonitoringCoordinator.shared.stopAndClear()
        authenticationState = .signedOut
        shops = []
        cartsByShop = [:]
        cafePlansByShop = [:]
        quickOrderSession = nil
        api.clearReadCaches()
        ImagePipeline.shared.removeAll()
        WidgetSnapshotSync.clear()
        AppIntentSearchIndexer.clear()
        Task { await OrderLiveActivityManager.shared.endAll() }
    }

    func bootstrap() async throws {
        guard authenticationState == .authenticated else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }
        do {
            let loadedShops = try await api.fetchShops()
            shops = loadedShops.map { shop in
                if shop.id == 7 { return Shop(id: shop.id, name: shop.name, kind: .cafeteria, isOpen: shop.isOpen) }
                return shop
            }
            let preferred = selectedShopID.flatMap { id in shops.contains(where: { $0.id == id }) ? id : nil }
                ?? shops.first(where: { $0.id == 5 })?.id
                ?? cafeShops.first?.id
                ?? shops.first?.id
            selectShop(preferred)
            await refreshCafeMetadata()
            await WidgetSnapshotSync.refresh(using: self, force: true)
            await AppIntentSearchIndexer.refresh(using: self)
            globalError = nil
        } catch is CancellationError {
            return
        } catch {
            globalError = error.localizedDescription
            throw error
        }
    }

    func selectShop(_ shopID: Int?) {
        selectedShopID = shopID
        preferences.lastShopID = shopID
    }

    func refreshCafeMetadata(force: Bool = false) async {
        if !force, let lastMetadataRefreshAt,
           Date.now.timeIntervalSince(lastMetadataRefreshAt) < 60 {
            return
        }
        lastMetadataRefreshAt = .now
        for shop in cafeShops {
            guard !Task.isCancelled else { return }
            async let cartRequest = try? await api.fetchCart(shopID: shop.id)
            async let planRequest = try? await api.fetchCafeSalesPlan(
                shopID: shop.id,
                forceRefresh: force
            )
            let cart = await cartRequest
            let plan = await planRequest
            if let cart { cartsByShop[shop.id] = cart }
            cafePlansByShop[shop.id] = plan
        }
    }

    func refreshCafePlan(shopID: Int, force: Bool = false) async {
        cafePlansByShop[shopID] = try? await api.fetchCafeSalesPlan(shopID: shopID, forceRefresh: force)
    }

    /// 첫 화면이 준비된 뒤 다음 탐색 화면의 데이터와 썸네일을 낮은 우선순위로 예열한다.
    func preloadPrimaryContent() async {
        guard authenticationState == .authenticated else { return }
        var imageURLs: [URL] = []

        if let dining = try? await api.fetchDiningMenu(shopID: diningShopID, date: .now) {
            imageURLs.append(contentsOf: dining.flatMap(\.courses).flatMap(\.menus).compactMap(\.imageURL))
        }

        for shop in cafeShops {
            guard !Task.isCancelled else { return }
            async let menuRequest = api.fetchCafeMenu(shopID: shop.id)
            async let recentRequest = api.fetchRecentOrders(shopID: shop.id)
            async let popularRequest = api.fetchPopularOrders(shopID: shop.id)

            let menus = (try? await menuRequest) ?? []
            let recent = (try? await recentRequest) ?? []
            let popular = (try? await popularRequest) ?? []
            imageURLs.append(contentsOf: menus.compactMap(\.thumbnailURL))
            imageURLs.append(contentsOf: recent.compactMap(\.thumbnailURL))
            imageURLs.append(contentsOf: popular.compactMap(\.thumbnailURL))

            for item in menus.prefix(4) {
                guard !Task.isCancelled else { return }
                _ = try? await api.fetchMenuDetail(displayID: item.displayID)
            }
        }

        ImagePipeline.shared.preload(imageURLs, targetSize: 96, limit: 64)
    }

    @discardableResult
    func refreshCart(shopID: Int) async throws -> Cart {
        let cart = try await api.fetchCart(shopID: shopID)
        cartsByShop[shopID] = Cart(id: cart.id, shopID: cart.shopID ?? shopID, items: cart.items)
        return cartsByShop[shopID] ?? cart
    }

    func addToCart(shopID: Int, goodsID: Int, quantity: Int = 1, options: [SelectedOption] = []) async throws {
        try await api.addToCart(shopID: shopID, goodsID: goodsID, quantity: quantity, options: options)
        try await refreshCart(shopID: shopID)
    }

    func setQuantity(shopID: Int, item: CartItem, quantity: Int) async throws {
        guard let cartID = cart(for: shopID).id else { throw OrderValidationError.emptyCart }
        if quantity <= 0 {
            try await api.deleteCartItems(cartID: cartID, itemIDs: [item.id])
        } else {
            try await api.updateCartQuantity(cartID: cartID, itemID: item.id, quantity: quantity)
        }
        try await refreshCart(shopID: shopID)
    }

    func deleteCartItem(shopID: Int, itemID: Int) async throws {
        guard let cartID = cart(for: shopID).id else { return }
        try await api.deleteCartItems(cartID: cartID, itemIDs: [itemID])
        try await refreshCart(shopID: shopID)
    }

    func toggleFavorite(shopID: Int, item: CafeMenuItem) {
        let favorite = FavoriteMenu(shopID: shopID, displayID: item.displayID, name: item.name)
        if favorites.contains(favorite) {
            favorites.remove(favorite)
        } else {
            favorites.insert(favorite)
        }
        preferences.favorites = favorites
        Task { await WidgetSnapshotSync.refresh(using: self, force: true) }
    }

    func isFavorite(shopID: Int, displayID: Int) -> Bool {
        favorites.contains { $0.shopID == shopID && $0.displayID == displayID }
    }

    func setDiningPreferences(_ values: [String]) {
        let normalized = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        diningPreferences = Array(Set(normalized)).sorted()
        preferences.diningPreferences = diningPreferences
    }

    func hasExactDiningPreference(named name: String) -> Bool {
        DiningPreferenceRules.containsExact(name, in: diningPreferences)
    }

    func toggleDiningPreference(named name: String) {
        setDiningPreferences(DiningPreferenceRules.toggling(name, in: diningPreferences))
    }

    func beginQuickOrder(shopID: Int, goodsID: Int, quantity: Int, options: [SelectedOption]) async throws {
        let snapshot = try await api.fetchCartSnapshot(shopID: shopID)
        do {
            if let cartID = snapshot.cart.id, !snapshot.cart.items.isEmpty {
                try await api.deleteCartItems(cartID: cartID, itemIDs: snapshot.cart.items.map(\.id))
            }
            try await api.addToCart(shopID: shopID, goodsID: goodsID, quantity: quantity, options: options)
            let isolated = try await api.fetchCart(shopID: shopID)
            guard isolated.items.count == 1,
                  isolated.items.first?.goodsID == goodsID,
                  isolated.items.first?.quantity == quantity
            else { throw QuickOrderError.isolationFailed }
            cartsByShop[shopID] = isolated
            quickOrderSession = QuickOrderSession(
                shopID: shopID,
                goodsID: goodsID,
                quantity: quantity,
                stashedLines: snapshot.restoreLines
            )
            selectShop(shopID)
        } catch {
            try? await restoreCart(shopID: shopID, lines: snapshot.restoreLines)
            throw error
        }
    }

    func cancelQuickOrder() async {
        guard let session = quickOrderSession else { return }
        quickOrderSession = nil
        try? await restoreCart(shopID: session.shopID, lines: session.stashedLines)
    }

    func completeQuickOrder() {
        quickOrderSession = nil
    }

    private func restoreCart(shopID: Int, lines: [CartRestoreLine]) async throws {
        try await api.clearCart(shopID: shopID)
        for line in lines {
            try await api.addToCart(
                shopID: shopID,
                goodsID: line.goodsID,
                quantity: line.quantity,
                options: line.options
            )
        }
        try await refreshCart(shopID: shopID)
    }
}

enum LoginValidationError: LocalizedError {
    case missingCredentials
    var errorDescription: String? { "이메일과 비밀번호를 입력해 주세요." }
}

enum QuickOrderError: LocalizedError {
    case isolationFailed
    var errorDescription: String? { "바로 주문용 장바구니를 안전하게 준비하지 못했습니다." }
}
