import Foundation
import Observation

private actor ShopMutationGate {
    private var lockedShopIDs: Set<Int> = []
    private var waiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    func acquire(shopID: Int) async {
        if lockedShopIDs.insert(shopID).inserted { return }
        await withCheckedContinuation { continuation in
            waiters[shopID, default: []].append(continuation)
        }
    }

    func release(shopID: Int) {
        if var shopWaiters = waiters[shopID], !shopWaiters.isEmpty {
            let next = shopWaiters.removeFirst()
            waiters[shopID] = shopWaiters.isEmpty ? nil : shopWaiters
            next.resume()
        } else {
            lockedShopIDs.remove(shopID)
        }
    }
}

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
    private let mutationGate = ShopMutationGate()

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
        self.quickOrderSession = preferences.quickOrderSession
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
            quickOrderSession = preferences.quickOrderSession
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

    func logout() async {
        if let session = quickOrderSession,
           !session.accountID.isEmpty,
           session.accountID == userIDHint {
            try? await restoreQuickOrderSession()
        }
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
            try await recoverQuickOrderIfNeeded()
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
            async let cartRequest = try? await refreshCart(shopID: shop.id)
            async let planRequest = try? await api.fetchCafeSalesPlan(
                shopID: shop.id,
                forceRefresh: force
            )
            let cart = await cartRequest
            let plan = await planRequest
            _ = cart
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
        try await withCartMutation(shopID: shopID) {
            try await refreshCartWithoutLock(shopID: shopID)
        }
    }

    @discardableResult
    private func refreshCartWithoutLock(shopID: Int) async throws -> Cart {
        let cart = try await api.fetchCart(shopID: shopID)
        cartsByShop[shopID] = Cart(id: cart.id, shopID: cart.shopID ?? shopID, items: cart.items)
        return cartsByShop[shopID] ?? cart
    }

    func addToCart(shopID: Int, goodsID: Int, quantity: Int = 1, options: [SelectedOption] = []) async throws {
        try await withCartMutation(shopID: shopID) {
            try await api.addToCart(shopID: shopID, goodsID: goodsID, quantity: quantity, options: options)
            try await refreshCartWithoutLock(shopID: shopID)
        }
    }

    func setQuantity(shopID: Int, item: CartItem, quantity: Int) async throws {
        try await withCartMutation(shopID: shopID) {
            try await setQuantityWithoutLock(shopID: shopID, itemID: item.id, quantity: quantity)
        }
    }

    func adjustQuantity(shopID: Int, itemID: Int, delta: Int) async throws {
        try await withCartMutation(shopID: shopID) {
            let current = try await api.fetchCart(shopID: shopID)
            guard let item = current.items.first(where: { $0.id == itemID }) else { return }
            cartsByShop[shopID] = current
            try await setQuantityWithoutLock(
                shopID: shopID,
                itemID: itemID,
                quantity: item.quantity + delta
            )
        }
    }

    func adjustGoodsQuantity(shopID: Int, goodsID: Int, delta: Int) async throws {
        try await withCartMutation(shopID: shopID) {
            let current = try await api.fetchCart(shopID: shopID)
            cartsByShop[shopID] = current
            if let item = current.items.first(where: { $0.goodsID == goodsID }) {
                try await setQuantityWithoutLock(
                    shopID: shopID,
                    itemID: item.id,
                    quantity: item.quantity + delta
                )
            } else if delta > 0 {
                try await api.addToCart(shopID: shopID, goodsID: goodsID, quantity: delta)
                try await refreshCartWithoutLock(shopID: shopID)
            }
        }
    }

    func deleteCartItem(shopID: Int, itemID: Int) async throws {
        try await withCartMutation(shopID: shopID) {
            guard let cartID = try await api.fetchCart(shopID: shopID).id else { return }
            try await api.deleteCartItems(cartID: cartID, itemIDs: [itemID])
            try await refreshCartWithoutLock(shopID: shopID)
        }
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
        guard !userIDHint.isEmpty else { throw QuickOrderError.accountMismatch }
        try await withCartMutation(shopID: shopID) {
            if quickOrderSession != nil { try await restoreQuickOrderSessionResilientWithoutLock() }

            let snapshot = try await api.fetchCartSnapshot(shopID: shopID)
            var session = QuickOrderSession(
                id: UUID(),
                accountID: userIDHint,
                shopID: shopID,
                goodsID: goodsID,
                quantity: quantity,
                options: options,
                stashedLines: snapshot.restoreLines,
                phase: .stashed
            )
            try persistQuickOrderSession(session)

            do {
                if let cartID = snapshot.cart.id, !snapshot.cart.items.isEmpty {
                    try await api.deleteCartItems(cartID: cartID, itemIDs: snapshot.cart.items.map(\.id))
                }
                try await api.addToCart(shopID: shopID, goodsID: goodsID, quantity: quantity, options: options)
                let isolated = try await api.fetchCartSnapshot(shopID: shopID)
                guard Self.matchesIsolatedCart(isolated, session: session) else {
                    throw QuickOrderError.isolationFailed
                }
                session.phase = .isolated
                try persistQuickOrderSession(session)
                cartsByShop[shopID] = isolated.cart
                selectShop(shopID)
            } catch {
                try? await restoreQuickOrderSessionResilientWithoutLock()
                throw error
            }
        }
    }

    func cancelQuickOrder() async throws {
        guard let session = quickOrderSession else { return }
        try await withCartMutation(shopID: session.shopID) {
            try await restoreQuickOrderSessionResilientWithoutLock()
        }
    }

    func completeQuickOrder() async throws {
        try await cancelQuickOrder()
    }

    func placeOrder(
        shopID: Int,
        reviewedCart: Cart,
        paymentReasonID: Int,
        isQuickOrder: Bool
    ) async throws -> Int? {
        try await withCartMutation(shopID: shopID) {
            let current = try await api.fetchCartSnapshot(shopID: shopID)
            guard current.cart.id == reviewedCart.id,
                  current.cart.items == reviewedCart.items
            else { throw OrderValidationError.cartChanged }
            if isQuickOrder {
                guard let session = quickOrderSession,
                      session.shopID == shopID,
                      Self.matchesIsolatedCart(current, session: session)
                else { throw QuickOrderError.isolationFailed }
                var submitting = session
                submitting.phase = .submitting
                try persistQuickOrderSession(submitting)
            }
            return try await api.placeOrder(
                shopID: shopID,
                cart: current.cart,
                paymentReasonID: paymentReasonID
            )
        }
    }

    private func recoverQuickOrderIfNeeded() async throws {
        guard let session = quickOrderSession else { return }
        guard !session.accountID.isEmpty, session.accountID == userIDHint else {
            throw QuickOrderError.accountMismatch
        }
        try await withCartMutation(shopID: session.shopID) {
            try await restoreQuickOrderSessionResilientWithoutLock()
        }
    }

    private func restoreQuickOrderSession() async throws {
        guard let session = quickOrderSession else { return }
        guard !session.accountID.isEmpty, session.accountID == userIDHint else {
            throw QuickOrderError.accountMismatch
        }
        try await withCartMutation(shopID: session.shopID) {
            try await restoreQuickOrderSessionResilientWithoutLock()
        }
    }

    /// 복구는 호출 화면의 Task가 취소되어도 서버 장바구니가 원상태가 될 때까지 계속한다.
    private func restoreQuickOrderSessionResilientWithoutLock() async throws {
        let recovery = Task { @MainActor [weak self] in
            guard let self else { return }
            try await self.restoreQuickOrderSessionWithoutLock()
        }
        try await recovery.value
    }

    private func restoreQuickOrderSessionWithoutLock() async throws {
        guard var session = quickOrderSession else { return }
        guard !session.accountID.isEmpty, session.accountID == userIDHint else {
            throw QuickOrderError.accountMismatch
        }
        session.phase = .restoring
        try persistQuickOrderSession(session)
        try await api.clearCart(shopID: session.shopID)
        for line in session.stashedLines {
            try await api.addToCart(
                shopID: session.shopID,
                goodsID: line.goodsID,
                quantity: line.quantity,
                options: line.options
            )
        }
        let restored = try await api.fetchCartSnapshot(shopID: session.shopID)
        guard Self.normalized(restored.restoreLines) == Self.normalized(session.stashedLines) else {
            throw QuickOrderError.restoreFailed
        }
        cartsByShop[session.shopID] = restored.cart
        try persistQuickOrderSession(nil)
    }

    private func setQuantityWithoutLock(shopID: Int, itemID: Int, quantity: Int) async throws {
        let current = try await api.fetchCart(shopID: shopID)
        guard let cartID = current.id else { throw OrderValidationError.emptyCart }
        if quantity <= 0 {
            try await api.deleteCartItems(cartID: cartID, itemIDs: [itemID])
        } else {
            try await api.updateCartQuantity(cartID: cartID, itemID: itemID, quantity: min(20, quantity))
        }
        try await refreshCartWithoutLock(shopID: shopID)
    }

    private func withCartMutation<Value>(
        shopID: Int,
        operation: () async throws -> Value
    ) async throws -> Value {
        await mutationGate.acquire(shopID: shopID)
        do {
            let value = try await operation()
            await mutationGate.release(shopID: shopID)
            return value
        } catch {
            await mutationGate.release(shopID: shopID)
            throw error
        }
    }

    private func persistQuickOrderSession(_ session: QuickOrderSession?) throws {
        try preferences.saveQuickOrderSession(session)
        quickOrderSession = session
    }

    private static func matchesIsolatedCart(_ snapshot: CartSnapshot, session: QuickOrderSession) -> Bool {
        normalized(snapshot.restoreLines) == normalized([
            CartRestoreLine(
                goodsID: session.goodsID,
                quantity: session.quantity,
                options: session.options
            )
        ])
    }

    private static func normalized(_ lines: [CartRestoreLine]) -> [String] {
        lines.map { line in
            let options = line.options
                .sorted { $0.optionID < $1.optionID }
                .map { "\($0.optionID):\($0.menuIDs.sorted().map(String.init).joined(separator: ","))" }
                .joined(separator: "|")
            return "\(line.goodsID)#\(line.quantity)#\(options)"
        }
        .sorted()
    }
}

enum LoginValidationError: LocalizedError {
    case missingCredentials
    var errorDescription: String? { "이메일과 비밀번호를 입력해 주세요." }
}

enum QuickOrderError: LocalizedError {
    case isolationFailed
    case restoreFailed
    case accountMismatch

    var errorDescription: String? {
        switch self {
        case .isolationFailed: "바로 주문용 장바구니를 안전하게 준비하지 못했습니다."
        case .restoreFailed: "기존 장바구니를 아직 복구하지 못했습니다. 다음 실행에서 다시 시도합니다."
        case .accountMismatch: "다른 계정의 장바구니 복구 정보가 남아 있어 바로 주문을 계속할 수 없습니다."
        }
    }
}
