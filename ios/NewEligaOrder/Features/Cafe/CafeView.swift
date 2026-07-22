import SwiftUI

struct CafeView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    let transitionNamespace: Namespace.ID
    private let searchHistoryStore = CafeSearchHistoryStore()
    @Binding private var isSearchPresented: Bool

    @State private var shopID: Int?
    @State private var actionError: String?
    @State private var searchText = ""
    @State private var searchHistory: [String] = []
    /// Cross-shop menu cache used only by search, which spans every shop at
    /// once — unlike a single shop's page (each owns its own menu state
    /// locally), search has no single "current shop" to scope to.
    @State private var searchMenusByShop: [Int: [CafeMenuItem]] = [:]
    /// The active page's own quick-item list, reported up via
    /// `CafeShopPageView.onQuickItemsLoaded` so the search field's
    /// suggestions can show it without CafeView owning per-shop menu state.
    @State private var quickItemsByShop: [Int: [CafeQuickItem]] = [:]
    @State private var isLoadingAllShopMenus = false
    @State private var searchErrorMessage: String?
    @State private var hasAttemptedAllShopMenus = false
    @State private var allShopMenuLoadGeneration = 0
    @State private var isSearchPullRefreshing = false

    init(
        initialShopID: Int?,
        transitionNamespace: Namespace.ID,
        isSearchPresented: Binding<Bool> = .constant(false)
    ) {
        self.transitionNamespace = transitionNamespace
        _isSearchPresented = isSearchPresented
        _shopID = State(initialValue: initialShopID)
    }

    private var activeShopID: Int { shopID ?? store.cafeShops.first?.id ?? 5 }
    private var isSearchActive: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var isSearchMode: Bool { isSearchPresented || isSearchActive }
    private var actionErrorBottomPadding: CGFloat {
        guard !isSearchMode else { return 0 }
        return 56
    }
    /// Ascending-floor order, regardless of the raw API order — also the
    /// order the shop `TabView` pages through.
    private var sortedShops: [Shop] { CafeShopSwitcherPolicy.sortedByFloor(store.cafeShops) }
    private var searchSections: [CafeMenuSearchSection] {
        CafeMenuFilter.sections(
            shops: store.cafeShops,
            menusByShop: searchMenusByShop,
            searchText: searchText,
            favoriteDisplayIDsByShop: favoriteDisplayIDsByShop
        )
    }
    private var favoriteDisplayIDsByShop: [Int: Set<Int>] {
        store.favorites.reduce(into: [:]) { result, favorite in
            result[favorite.shopID, default: []].insert(favorite.displayID)
        }
    }
    private var activeShopIDBinding: Binding<Int> {
        Binding(get: { activeShopID }, set: { selectShop($0) })
    }

    var body: some View {
        Group {
            if isSearchActive {
                searchContent
            } else {
                // A native paged `TabView` tracks the finger 1:1 during the
                // drag — the adjacent shop's page slides in right alongside
                // it, and the direction always matches the gesture because
                // it's driven by the same `ForEach` order the pages are
                // laid out in. The previous approach (a custom pan gesture
                // that only fired once on release, then jumped to a
                // pre-computed slide direction) couldn't show that live
                // motion and could occasionally guess the wrong direction.
                TabView(selection: activeShopIDBinding) {
                    ForEach(sortedShops) { shop in
                        CafeShopPageView(
                            shopID: shop.id,
                            isSearchPresented: isSearchPresented,
                            onNavigateAway: {
                                recordCurrentSearch()
                                isSearchPresented = false
                            },
                            onMutationError: { actionError = $0 },
                            onQuickItemsLoaded: { quickItemsByShop[shop.id] = $0 }
                        )
                        .tag(shop.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // Nothing to pop back to at this tab's root — freeing the
                // left edge from the system back-swipe lets a leftward drag
                // that starts near it still page backward. Re-enabled
                // whenever a detail screen is pushed, so back-swipe still
                // works there.
                .disablesInteractivePopGesture(while: !isSearchMode && router.cafePath.isEmpty)
            }
        }
        .modifier(
            CafeSearchInterfaceModifier(
                text: $searchText,
                isPresented: $isSearchPresented,
                history: searchHistory,
                quickItems: quickItemsByShop[activeShopID] ?? []
            )
        )
        .onSubmit(of: .search) {
            recordCurrentSearch()
        }
        .onChange(of: searchText) { previousValue, newValue in
            if !previousValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                recordSearch(previousValue)
            }
        }
        .navigationTitle("카페")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            // Owned entirely by CafeView — a header row right under the nav
            // bar instead of floating above the tab bar. Swiping the shop
            // switcher itself still selects a shop by tapping a chip; the
            // whole screen now handles the swipe-to-step gesture instead.
            if !isSearchMode {
                CafeShopHeaderBar(
                    shops: store.cafeShops,
                    selectedShopID: activeShopID,
                    selectShop: selectShop,
                    trailingAccessory: CafeShopHeaderBar.TrailingAccessory(
                        systemImage: "magnifyingglass",
                        accessibilityLabel: "메뉴 검색",
                        accessibilityIdentifier: "cafe.search.accessory",
                        action: { isSearchPresented = true }
                    )
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if let actionError {
                Text(actionError)
                    .font(.callout)
                    .padding()
                    .appGlassSurface(cornerRadius: 22, tint: .red)
                    .padding()
                    .padding(.bottom, actionErrorBottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .task(id: store.userIDHint) {
            searchHistory = searchHistoryStore.history(accountID: store.userIDHint)
        }
        .task(id: isSearchActive) {
            if isSearchActive { await loadAllShopMenus() }
        }
        .task(id: actionError) {
            guard actionError != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation { actionError = nil }
        }
        .onChange(of: store.selectedShopID) { _, selectedShopID in
            guard
                let selectedShopID,
                store.cafeShops.contains(where: { $0.id == selectedShopID })
            else { return }
            selectShop(selectedShopID)
        }
        .onChange(of: isSearchPresented) { wasPresented, isPresented in
            if wasPresented, !isPresented {
                recordCurrentSearch()
                searchText = ""
            }
        }
        .onDisappear {
            recordCurrentSearch()
        }
        .animation(.snappy, value: isSearchMode)
    }

    @ViewBuilder
    private var searchContent: some View {
        if (!hasAttemptedAllShopMenus || isLoadingAllShopMenus), searchSections.isEmpty {
            LoadingContentView(title: "모든 카페 매장의 메뉴를 검색하는 중…")
        } else if let searchErrorMessage, searchSections.isEmpty {
            FailureContentView(message: searchErrorMessage) {
                Task { await loadAllShopMenus(force: true) }
            }
        } else if searchSections.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            allShopSearchList
        }
    }

    private var allShopSearchList: some View {
        List {
            if isLoadingAllShopMenus && !isSearchPullRefreshing {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("다른 매장 메뉴도 확인하는 중…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } else if let searchErrorMessage {
                Section {
                    Label(searchErrorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(searchSections) { shopSection in
                let grouped = CafeMenuFilter.prioritySections(
                    from: shopSection.items,
                    favoriteDisplayIDs: favoriteDisplayIDs(for: shopSection.shop.id)
                )
                ForEach(grouped) { section in
                    Section {
                        CafePrioritySectionHeader(
                            group: section.group,
                            count: section.items.count,
                            shopName: shopSection.shop.name
                        )
                        .listRowInsets(.init(top: 0, leading: 16, bottom: 2, trailing: 16))
                        .listRowSeparator(.hidden)

                        ForEach(section.items) { item in
                            menuRow(item, shopID: shopSection.shop.id)
                        }
                    }
                    .listSectionSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 1)
        .refreshable {
            isSearchPullRefreshing = true
            await loadAllShopMenus(force: true)
            isSearchPullRefreshing = false
        }
        .appScrollEdgeStyle()
    }

    private func loadAllShopMenus(force: Bool = false) async {
        allShopMenuLoadGeneration &+= 1
        let generation = allShopMenuLoadGeneration
        isLoadingAllShopMenus = true
        searchErrorMessage = nil
        defer {
            if generation == allShopMenuLoadGeneration {
                isLoadingAllShopMenus = false
                hasAttemptedAllShopMenus = true
            }
        }

        let targets = store.cafeShops.filter { force || searchMenusByShop[$0.id] == nil }
        let api = store.api
        let results = await withTaskGroup(
            of: CafeShopMenuLoadResult.self,
            returning: [CafeShopMenuLoadResult].self
        ) { group in
            for shop in targets {
                group.addTask {
                    do {
                        let items = try await api.fetchCafeMenu(
                            shopID: shop.id,
                            forceRefresh: force
                        )
                        return CafeShopMenuLoadResult(shopID: shop.id, shopName: shop.name, items: items)
                    } catch {
                        return CafeShopMenuLoadResult(shopID: shop.id, shopName: shop.name, items: nil)
                    }
                }
            }
            var values: [CafeShopMenuLoadResult] = []
            for await value in group { values.append(value) }
            return values
        }
        guard !Task.isCancelled, generation == allShopMenuLoadGeneration else { return }

        var failedShopNames: [String] = []
        for result in results {
            if let items = result.items {
                searchMenusByShop[result.shopID] = items
                ImagePipeline.shared.preload(items.compactMap(\.thumbnailURL), targetSize: 96)
            } else {
                failedShopNames.append(result.shopName)
            }
        }
        if !failedShopNames.isEmpty {
            searchErrorMessage = "일부 매장 메뉴를 불러오지 못했습니다: \(failedShopNames.joined(separator: ", "))"
        }
    }

    private func selectShop(_ id: Int) {
        guard id != activeShopID else { return }
        shopID = id
        store.selectShop(id)
    }

    private func quantity(for goodsID: Int?, shopID: Int) -> Int {
        guard let goodsID else { return 0 }
        return store.cart(for: shopID).items.first { $0.goodsID == goodsID }?.quantity ?? 0
    }

    private func favoriteDisplayIDs(for shopID: Int) -> Set<Int> {
        favoriteDisplayIDsByShop[shopID] ?? []
    }

    private func menuRow(_ item: CafeMenuItem, shopID: Int) -> some View {
        CafeMenuRow(
            item: item,
            isFavorite: store.isFavorite(shopID: shopID, displayID: item.displayID),
            quantity: quantity(for: item.goodsID, shopID: shopID),
            orderState: CafeRules.state(for: store.cafePlansByShop[shopID] ?? nil),
            toggleFavorite: { store.toggleFavorite(shopID: shopID, displayID: item.displayID, name: item.name) },
            decrease: { mutate(item, shopID: shopID, delta: -1) },
            increase: { mutate(item, shopID: shopID, delta: 1) },
            openDetail: { openDetail(item, shopID: shopID) },
            quickOrder: { openQuickOrder(item, shopID: shopID) }
        )
        .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private func openDetail(_ item: CafeMenuItem, shopID: Int) {
        recordCurrentSearch()
        isSearchPresented = false
        store.selectShop(shopID)
        router.push(.menu(shopID: shopID, displayID: item.displayID), on: .cafe)
    }

    private func openQuickOrder(_ item: CafeMenuItem, shopID: Int) {
        recordCurrentSearch()
        isSearchPresented = false
        store.selectShop(shopID)
        router.push(.quickOrder(shopID: shopID, displayID: item.displayID), on: .cafe)
    }

    private func recordCurrentSearch() {
        guard isSearchActive else { return }
        recordSearch(searchText)
    }

    private func recordSearch(_ query: String) {
        searchHistory = searchHistoryStore.record(query, accountID: store.userIDHint)
    }

    private func mutate(_ menu: CafeMenuItem, shopID: Int, delta: Int) {
        guard let goodsID = menu.goodsID else { return }
        actionError = nil
        Task {
            do {
                try await store.adjustGoodsQuantity(
                    shopID: shopID,
                    goodsID: goodsID,
                    delta: delta
                )
            } catch {
                withAnimation { actionError = error.localizedDescription }
            }
        }
    }
}

/// One shop's full page — category picker, order-availability banner, and
/// menu list/loading/error/empty states — owning its own state so the
/// enclosing `TabView(.page)` can keep every shop's page alive and page
/// between them with live, finger-tracked motion (SwiftUI can't do that
/// across pages that share one mutable state slot the way the previous
/// single-active-shop design worked).
private struct CafeShopPageView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    let shopID: Int
    let isSearchPresented: Bool
    let onNavigateAway: () -> Void
    let onMutationError: (String) -> Void
    let onQuickItemsLoaded: ([CafeQuickItem]) -> Void

    @State private var categories: [CafeCategory] = []
    @State private var selectedCategoryID: Int?
    @State private var menus: [CafeMenuItem] = []
    @State private var quickItems: [CafeQuickItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    /// Suppresses the custom loading indicators while `.refreshable`'s own
    /// pull-to-refresh spinner is visible, so the two don't show up doubled.
    @State private var isPullRefreshing = false
    @State private var hasLoadedOnce = false

    private var orderState: CafeOrderState { CafeRules.state(for: store.cafePlansByShop[shopID] ?? nil) }
    private var favoriteDisplayIDs: Set<Int> {
        Set(store.favorites.filter { $0.shopID == shopID }.map(\.displayID))
    }
    private var visibleMenus: [CafeMenuItem] {
        CafeMenuFilter.items(
            in: menus,
            selectedCategoryID: selectedCategoryID,
            searchText: "",
            favoriteDisplayIDs: favoriteDisplayIDs
        )
    }
    private var prioritySections: [CafeMenuPrioritySection] {
        CafeMenuFilter.prioritySections(from: visibleMenus, favoriteDisplayIDs: favoriteDisplayIDs)
    }
    private var shopName: String {
        store.cafeShops.first(where: { $0.id == shopID })?.name ?? "매장 선택"
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isSearchPresented {
                categoryPicker
                orderBanner
            }
            content
        }
        .task {
            guard !hasLoadedOnce else { return }
            hasLoadedOnce = true
            await load(replacingContent: true)
        }
        .sensoryFeedback(.selection, trigger: selectedCategoryID)
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 22) {
                CafeCategoryTab(title: "전체", count: menus.count, isSelected: selectedCategoryID == nil) {
                    selectedCategoryID = nil
                }
                ForEach(categories.filter(\.isVisibleOnMobile)) { category in
                    CafeCategoryTab(
                        title: category.name,
                        count: category.goodsCount,
                        isSelected: selectedCategoryID == category.id
                    ) {
                        selectedCategoryID = category.id
                    }
                }
            }
            .padding(.horizontal)
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .frame(minHeight: 48)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var orderBanner: some View {
        switch orderState {
        case .checking:
            CafeOrderCheckingCard()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        case .closed(let closure):
            CafeOrderAvailabilityCard(closure: closure, shopName: shopName)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        case .open:
            EmptyView()
        }
    }

    @ViewBuilder
    private var content: some View {
        // Every branch gets the same explicit full-size frame — without it,
        // `ContentUnavailableView`/`CafeMenuListPlaceholder` size to their
        // own content instead of filling the page like `List` does, so a
        // page's overall height could change out from under `TabView(.page)`
        // right as its data resolves. If that happens while the user is
        // mid-swipe, the paging scroll view's animation can lock up between
        // two pages instead of settling normally.
        if isLoading && menus.isEmpty {
            CafeMenuListPlaceholder()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, menus.isEmpty {
            FailureContentView(message: errorMessage) {
                Task { await load(replacingContent: menus.isEmpty) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleMenus.isEmpty, selectedCategoryID != nil {
            ContentUnavailableView(
                "이 카테고리에 메뉴가 없습니다",
                systemImage: "cup.and.saucer",
                description: Text("다른 카테고리를 선택해 보세요.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if menus.isEmpty {
            ContentUnavailableView(
                "등록된 메뉴가 없습니다",
                systemImage: "cup.and.saucer",
                description: Text("잠시 후 다시 확인해 주세요.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            menuList
        }
    }

    private var menuList: some View {
        List {
            if !quickItems.isEmpty {
                Section("최근·인기 메뉴") {
                    quickMenuRail
                        .listRowSeparator(.hidden)
                }
                .listSectionSeparator(.hidden)
            }

            ForEach(prioritySections) { section in
                Section {
                    CafePrioritySectionHeader(
                        group: section.group,
                        count: section.items.count
                    )
                    .listRowInsets(.init(top: 0, leading: 16, bottom: 2, trailing: 16))
                    .listRowSeparator(.hidden)

                    ForEach(section.items) { item in
                        menuRow(item)
                    }
                }
                .listSectionSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 1)
        .refreshable {
            isPullRefreshing = true
            await load(replacingContent: false, forceRefresh: true)
            isPullRefreshing = false
        }
        .overlay(alignment: .top) {
            if isLoading && !isPullRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
                    .background(.regularMaterial, in: Circle())
                    .accessibilityLabel("메뉴 새로고침 중")
            }
        }
        .appScrollEdgeStyle()
    }

    private var quickMenuRail: some View {
        ScrollView(.horizontal) {
            LazyHStack {
                ForEach(quickItems) { item in
                    CafeQuickItemButton(item: item, shopID: shopID)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
    }

    private func load(replacingContent: Bool, forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        if replacingContent {
            selectedCategoryID = nil
        }
        do {
            async let loadedMenus = store.api.fetchCafeMenu(shopID: shopID, forceRefresh: forceRefresh)
            async let recent = store.api.fetchRecentOrders(shopID: shopID, forceRefresh: forceRefresh)
            async let popular = store.api.fetchPopularOrders(shopID: shopID, forceRefresh: forceRefresh)
            let newMenus = try await loadedMenus
            let newCategories = try await store.api.fetchCafeCategories(shopID: shopID)
            let combined = (try? await recent) ?? []
            let popularItems = (try? await popular) ?? []
            let uniqueItems = (combined + popularItems).reduce(into: [Int: CafeQuickItem]()) { result, item in
                result[item.displayID] = result[item.displayID] ?? item
            }
            let newQuickItems = Array(uniqueItems.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }.prefix(12))
            guard !Task.isCancelled else { return }
            // Cross-fades the loading skeleton (or a stale previous list)
            // into the freshly loaded menu instead of an instant pop, so a
            // shop switch reads as one continuous motion rather than a
            // slide followed by an abrupt content swap.
            withAnimation(.easeOut(duration: 0.22)) {
                categories = newCategories
                menus = newMenus
                quickItems = newQuickItems
            }
            onQuickItemsLoaded(newQuickItems)
            ImagePipeline.shared.preload(
                newMenus.compactMap(\.thumbnailURL) + newQuickItems.compactMap(\.thumbnailURL),
                targetSize: 96
            )
            await store.refreshCafePlan(shopID: shopID, force: forceRefresh)
            _ = try? await store.refreshCart(shopID: shopID)
        } catch is CancellationError {
            return
        } catch {
            withAnimation(.easeOut(duration: 0.22)) {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func quantity(for goodsID: Int?) -> Int {
        guard let goodsID else { return 0 }
        return store.cart(for: shopID).items.first { $0.goodsID == goodsID }?.quantity ?? 0
    }

    private func menuRow(_ item: CafeMenuItem) -> some View {
        CafeMenuRow(
            item: item,
            isFavorite: store.isFavorite(shopID: shopID, displayID: item.displayID),
            quantity: quantity(for: item.goodsID),
            orderState: orderState,
            toggleFavorite: { store.toggleFavorite(shopID: shopID, displayID: item.displayID, name: item.name) },
            decrease: { mutate(item, delta: -1) },
            increase: { mutate(item, delta: 1) },
            openDetail: { openDetail(item) },
            quickOrder: { openQuickOrder(item) }
        )
        .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private func openDetail(_ item: CafeMenuItem) {
        onNavigateAway()
        store.selectShop(shopID)
        router.push(.menu(shopID: shopID, displayID: item.displayID), on: .cafe)
    }

    private func openQuickOrder(_ item: CafeMenuItem) {
        onNavigateAway()
        store.selectShop(shopID)
        router.push(.quickOrder(shopID: shopID, displayID: item.displayID), on: .cafe)
    }

    private func mutate(_ menu: CafeMenuItem, delta: Int) {
        guard let goodsID = menu.goodsID else { return }
        Task {
            do {
                try await store.adjustGoodsQuantity(shopID: shopID, goodsID: goodsID, delta: delta)
            } catch {
                onMutationError(error.localizedDescription)
            }
        }
    }
}

private struct CafeSearchInterfaceModifier: ViewModifier {
    @Binding var text: String
    @Binding var isPresented: Bool
    let history: [String]
    let quickItems: [CafeQuickItem]

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if isPresented {
                searchable(content)
            } else {
                content
            }
        } else {
            legacySearchable(content)
        }
    }

    private func searchable(_ content: Content) -> some View {
        withSuggestions(
            content.searchable(
                text: $text,
                isPresented: $isPresented,
                placement: .toolbar,
                prompt: "모든 매장의 메뉴 검색"
            )
        )
    }

    private func legacySearchable(_ content: Content) -> some View {
        withSuggestions(
            content.searchable(
                text: $text,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "모든 매장의 메뉴 검색"
            )
        )
    }

    private func withSuggestions<SearchContent: View>(_ content: SearchContent) -> some View {
        content.searchSuggestions {
            if text.isEmpty {
                if !history.isEmpty {
                    Section("최근 검색") {
                        ForEach(history, id: \.self) { query in
                            Label(query, systemImage: "clock.arrow.circlepath")
                                .searchCompletion(query)
                        }
                    }
                }

                if !quickItems.isEmpty {
                    Section("최근·인기 메뉴") {
                        ForEach(quickItems.prefix(5)) { item in
                            Label(item.name, systemImage: "sparkles")
                                .searchCompletion(item.name)
                        }
                    }
                }
            }
        }
    }
}

struct CafeOrderCheckingCard: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("주문 가능 시간을 확인하고 있어요")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("주문 가능 시간을 확인하고 있어요")
    }
}

struct CafeOrderAvailabilityCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let closure: CafeOrderClosure
    let shopName: String

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    statusIcon
                    content
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    statusIcon
                    content
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            closure.reason.tint.opacity(0.09),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(closure.reason.tint.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("cafe.availability.\(closure.reason.accessibilityID)")
    }

    private var statusIcon: some View {
        Image(systemName: closure.reason.systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 42, height: 42)
            .background(closure.reason.tint.opacity(0.14), in: Circle())
            .accessibilityHidden(true)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(closure.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(detailText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let schedule = closure.schedule {
                Label(schedule, systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(closure.reason.tint.opacity(0.10), in: Capsule())
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailText: String {
        closure.reason == .holiday
            ? "\(shopName) 매장은 오늘 운영하지 않아요."
            : closure.detail
    }

    private var accessibilityLabel: String {
        [closure.title, detailText, closure.schedule]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

/// One item in the "최근·인기 메뉴" rail. Long-press actions use a local
/// `@State`-driven confirmation dialog rather than `.contextMenu` —
/// `.contextMenu` on a button inside a single shared `List` row (this rail
/// is one List row hosting many buttons) isn't reliably scoped per button;
/// long-pressing any item ended up showing the wrong item's menu. Owning
/// the presented state per-instance here guarantees it's tied to the exact
/// item that was pressed.
private struct CafeQuickItemButton: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    let item: CafeQuickItem
    let shopID: Int
    @State private var showsActions = false

    private var isFavorite: Bool { store.isFavorite(shopID: shopID, displayID: item.displayID) }

    var body: some View {
        Button {
            router.push(.menu(shopID: shopID, displayID: item.displayID), on: .cafe)
        } label: {
            VStack(alignment: .leading) {
                CafeMenuThumbnail(
                    url: item.thumbnailURL,
                    size: 72,
                    isSoldOut: item.isSoldOut
                )
                Text(item.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
            }
            .frame(width: 80, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(item.displayID == 0)
        .onLongPressGesture {
            guard item.displayID != 0 else { return }
            showsActions = true
        }
        .confirmationDialog(item.name, isPresented: $showsActions, titleVisibility: .visible) {
            Button(isFavorite ? "즐겨찾기 해제" : "즐겨찾기에 추가") {
                store.toggleFavorite(shopID: shopID, displayID: item.displayID, name: item.name)
            }
            Button("상세 보기") {
                router.push(.menu(shopID: shopID, displayID: item.displayID), on: .cafe)
            }
            Button("취소", role: .cancel) {}
        }
        .accessibilityLabel(item.isSoldOut ? "\(item.name), 품절" : item.name)
        .accessibilityHint(
            item.isSoldOut
                ? "메뉴 상세 정보를 엽니다. 현재 품절입니다"
                : "메뉴 상세 정보를 엽니다"
        )
        .accessibilityAction(
            named: Text(isFavorite ? "즐겨찾기 해제" : "즐겨찾기에 추가")
        ) {
            store.toggleFavorite(shopID: shopID, displayID: item.displayID, name: item.name)
        }
        // `.contextMenu` normally gives a tick when it appears — since this
        // uses a plain long-press instead, that has to be added back by hand.
        .sensoryFeedback(.selection, trigger: showsActions)
        .sensoryFeedback(.selection, trigger: isFavorite)
    }
}

private struct CafePrioritySectionHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let group: CafeMenuPriorityGroup
    let count: Int
    var shopName: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Divider()

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 5) {
                    headerTitle
                    Text("메뉴 \(count)개")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 8) {
                    headerTitle
                    Spacer(minLength: 8)
                    Text("\(count)개")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.primary)
                }
            }
        }
        .textCase(nil)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("cafe.section.\(group.rawValue)")
    }

    private var headerTitle: some View {
        HStack(spacing: 8) {
            Image(systemName: group.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(group.tint)
                .frame(minWidth: 32, minHeight: 32)
                .background(group.tint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                if let shopName {
                    Text(shopName)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(group.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var accessibilityLabel: String {
        if let shopName {
            return "\(shopName), \(group.title), 메뉴 \(count)개"
        }
        return "\(group.title), 메뉴 \(count)개"
    }
}

private extension CafeMenuPriorityGroup {
    var tint: Color {
        switch self {
        case .favorite: .yellow
        case .best: .orange
        case .new: .blue
        case .standard: .secondary
        }
    }
}

private extension CafeOrderClosureReason {
    var tint: Color {
        switch self {
        case .holiday: .orange
        case .breakTime: .blue
        case .paused: .orange
        case .outsideHours: .secondary
        case .lastOrderEnded: .indigo
        }
    }

    var accessibilityID: String {
        switch self {
        case .holiday: "holiday"
        case .breakTime: "break"
        case .paused: "paused"
        case .outsideHours: "closed"
        case .lastOrderEnded: "last-order"
        }
    }
}

private struct CafeCategoryTab: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    if count > 0 {
                        Text("\(count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Capsule()
                    .fill(isSelected ? Color.accentColor : .clear)
                    .frame(height: 3)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(title) 카테고리")
        .accessibilityValue(count > 0 ? "메뉴 \(count)개" : "")
    }
}

private struct CafeShopMenuLoadResult: Sendable {
    let shopID: Int
    let shopName: String
    let items: [CafeMenuItem]?
}

#if DEBUG
struct CafeHolidayFixtureView: View {
    private let closure = CafeOrderClosure(
        reason: .holiday,
        title: "오늘은 휴무예요",
        detail: "선택한 매장은 오늘 운영하지 않아요.",
        schedule: "다음 영업 · 월요일 09:00–19:00"
    )

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CafeOrderAvailabilityCard(closure: closure, shopName: "엘리가 카페")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Spacer()
            }
            .navigationTitle("카페")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct CafePrioritySectionsFixtureView: View {
    private var sections: [CafeMenuPrioritySection] {
        let allSections = CafeMenuFilter.prioritySections(
            from: [
                Self.fixtureItem(id: 1, name: "즐겨찾는 바닐라 라떼", label: nil),
                Self.fixtureItem(id: 2, name: "시그니처 아메리카노", label: "BEST"),
                Self.fixtureItem(id: 3, name: "제주 말차 크림 라떼", label: "NEW"),
                Self.fixtureItem(id: 4, name: "디카페인 콜드브루", label: nil),
                Self.fixtureItem(id: 5, name: "품절 테스트 메뉴", label: nil, isSoldOut: true),
            ],
            favoriteDisplayIDs: [1]
        )

        guard
            let rawGroup = ProcessInfo.processInfo.environment["CAFE_FIXTURE_GROUP"],
            let group = CafeMenuPriorityGroup(rawValue: rawGroup),
            let section = allSections.first(where: { $0.group == group })
        else { return allSections }

        return [CafeMenuPrioritySection(group: section.group, items: Array(section.items.prefix(1)))]
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections) { section in
                    Section {
                        CafePrioritySectionHeader(
                            group: section.group,
                            count: section.items.count
                        )
                        .listRowInsets(.init(top: 0, leading: 16, bottom: 2, trailing: 16))
                        .listRowSeparator(.hidden)

                        ForEach(section.items) { item in
                            CafeMenuRow(
                                item: item,
                                isFavorite: item.displayID == 1,
                                quantity: item.displayID == 1 ? 2 : 0,
                                orderState: .open(hours: "08:00–18:00"),
                                toggleFavorite: {},
                                decrease: {},
                                increase: {},
                                openDetail: {},
                                quickOrder: {}
                            )
                            .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                    .listSectionSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .navigationTitle("카페 메뉴")
        }
    }

    private static func fixtureItem(
        id: Int,
        name: String,
        label: String?,
        isSoldOut: Bool = false
    ) -> CafeMenuItem {
        CafeMenuItem(
            displayID: id,
            goodsID: id,
            name: name,
            categoryID: 1,
            category: "음료",
            price: 4_500,
            isSoldOut: isSoldOut,
            description: "부드럽고 균형 잡힌 풍미",
            calorie: nil,
            nutrition: nil,
            label: label,
            displayName: name,
            thumbnailURL: nil
        )
    }
}
#endif
