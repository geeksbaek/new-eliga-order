import SwiftUI

struct CafeView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    let transitionNamespace: Namespace.ID

    @State private var shopID: Int?
    @State private var categories: [CafeCategory] = []
    @State private var selectedCategoryID: Int?
    @State private var menus: [CafeMenuItem] = []
    @State private var quickItems: [CafeQuickItem] = []
    @State private var loadingShopID: Int?
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var searchText = ""
    @State private var menusByShop: [Int: [CafeMenuItem]] = [:]
    @State private var categoriesByShop: [Int: [CafeCategory]] = [:]
    @State private var quickItemsByShop: [Int: [CafeQuickItem]] = [:]
    @State private var isLoadingAllShopMenus = false
    @State private var searchErrorMessage: String?
    @State private var hasAttemptedAllShopMenus = false
    @State private var loadedShopIDs: Set<Int> = []
    @State private var menuScrollPosition = ScrollPosition(idType: Int.self)

    init(initialShopID: Int?, transitionNamespace: Namespace.ID) {
        self.transitionNamespace = transitionNamespace
        _shopID = State(initialValue: initialShopID)
    }

    private var activeShopID: Int { shopID ?? store.cafeShops.first?.id ?? 5 }
    private var isLoading: Bool { loadingShopID != nil }
    private var isSearchActive: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var orderState: CafeOrderState { CafeRules.state(for: store.cafePlansByShop[activeShopID] ?? nil) }
    private var visibleMenus: [CafeMenuItem] {
        CafeMenuFilter.items(
            in: menus,
            selectedCategoryID: selectedCategoryID,
            searchText: searchText,
            favoriteDisplayIDs: favoriteDisplayIDs(for: activeShopID)
        )
    }
    private var searchSections: [CafeMenuSearchSection] {
        CafeMenuFilter.sections(
            shops: store.cafeShops,
            menusByShop: menusByShop,
            searchText: searchText,
            favoriteDisplayIDsByShop: favoriteDisplayIDsByShop
        )
    }
    private var favoriteDisplayIDsByShop: [Int: Set<Int>] {
        store.favorites.reduce(into: [:]) { result, favorite in
            result[favorite.shopID, default: []].insert(favorite.displayID)
        }
    }
    private var prioritySections: [CafeMenuPrioritySection] {
        CafeMenuFilter.prioritySections(
            from: visibleMenus,
            favoriteDisplayIDs: favoriteDisplayIDs(for: activeShopID)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isSearchActive {
                categoryPicker
            }
            orderBanner
            ZStack {
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "모든 매장의 메뉴 검색"
        )
        .searchSuggestions {
            if searchText.isEmpty {
                ForEach(quickItems.prefix(5)) { item in
                    Label(item.name, systemImage: "clock.arrow.circlepath")
                        .searchCompletion(item.name)
                }
            }
        }
        .navigationTitle("카페")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                shopMenu
            }
        }
        .overlay(alignment: .bottom) {
            if let actionError {
                Text(actionError)
                    .font(.callout)
                    .padding()
                    .appGlassSurface(cornerRadius: 22, tint: .red)
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .task(id: activeShopID) {
            guard !loadedShopIDs.contains(activeShopID) else { return }
            await load(shopID: activeShopID, replacingContent: true)
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
        .sensoryFeedback(.selection, trigger: selectedCategoryID)
    }

    private var shopMenu: some View {
        Menu {
            ForEach(store.cafeShops) { shop in
                Button {
                    selectShop(shop.id)
                } label: {
                    if shop.id == activeShopID {
                        Label(shop.name, systemImage: "checkmark")
                    } else {
                        Text(shop.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(activeShopName)
                    .font(.headline)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("카페 매장")
        .accessibilityValue(activeShopName)
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
            Label("주문 가능 시간을 확인하는 중입니다", systemImage: "clock.arrow.circlepath")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .accessibilityElement(children: .combine)
        case .closed(let message):
            Label(message, systemImage: "clock.badge.exclamationmark")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .accessibilityElement(children: .combine)
        case .open:
            EmptyView()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isSearchActive {
            searchContent
        } else if isLoading && menus.isEmpty {
            CafeMenuListPlaceholder()
        } else if let errorMessage, menus.isEmpty {
            FailureContentView(message: errorMessage) {
                Task { await load(shopID: activeShopID, replacingContent: menus.isEmpty) }
            }
        } else if visibleMenus.isEmpty, !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if visibleMenus.isEmpty, selectedCategoryID != nil {
            ContentUnavailableView(
                "이 카테고리에 메뉴가 없습니다",
                systemImage: "cup.and.saucer",
                description: Text("다른 카테고리를 선택해 보세요.")
            )
        } else if menus.isEmpty {
            ContentUnavailableView(
                "등록된 메뉴가 없습니다",
                systemImage: "cup.and.saucer",
                description: Text("잠시 후 다시 확인해 주세요.")
            )
        } else {
            menuList
        }
    }

    private var menuList: some View {
        List {
            if !quickItems.isEmpty {
                Section("최근·인기 메뉴") {
                    quickMenuRail
                }
            }

            ForEach(prioritySections) { section in
                Section {
                    ForEach(section.items) { item in
                        menuRow(item, shopID: activeShopID)
                    }
                } header: {
                    Label(section.group.title, systemImage: section.group.systemImage)
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 1)
        .scrollPosition($menuScrollPosition)
        .refreshable { await load(shopID: activeShopID, replacingContent: false, forceRefresh: true) }
        .overlay(alignment: .top) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
                    .background(.regularMaterial, in: Circle())
                    .accessibilityLabel("메뉴 새로고침 중")
            }
        }
        .appScrollEdgeStyle()
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
            if isLoadingAllShopMenus {
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
                        ForEach(section.items) { item in
                            menuRow(item, shopID: shopSection.shop.id)
                        }
                    } header: {
                        Text("\(shopSection.shop.name) · \(section.group.title)")
                    }
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 1)
        .refreshable { await loadAllShopMenus(force: true) }
        .appScrollEdgeStyle()
    }

    private var quickMenuRail: some View {
        ScrollView(.horizontal) {
            LazyHStack {
                ForEach(quickItems) { item in
                    Button {
                        router.push(.menu(shopID: activeShopID, displayID: item.displayID), on: .cafe)
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
                    .accessibilityLabel(item.isSoldOut ? "\(item.name), 품절" : item.name)
                    .accessibilityHint(
                        item.isSoldOut
                            ? "메뉴 상세 정보를 엽니다. 현재 품절입니다"
                            : "메뉴 상세 정보를 엽니다"
                    )
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
    }

    private func load(shopID id: Int, replacingContent: Bool, forceRefresh: Bool = false) async {
        loadingShopID = id
        defer {
            if loadingShopID == id { loadingShopID = nil }
        }
        errorMessage = nil
        if replacingContent {
            selectedCategoryID = nil
            categories = categoriesByShop[id] ?? []
            menus = menusByShop[id] ?? []
            quickItems = quickItemsByShop[id] ?? []
        }
        store.selectShop(id)
        do {
            async let loadedMenus = store.api.fetchCafeMenu(shopID: id, forceRefresh: forceRefresh)
            async let recent = store.api.fetchRecentOrders(shopID: id, forceRefresh: forceRefresh)
            async let popular = store.api.fetchPopularOrders(shopID: id, forceRefresh: forceRefresh)
            let newMenus = try await loadedMenus
            let newCategories = try await store.api.fetchCafeCategories(shopID: id)
            let combined = (try? await recent) ?? []
            let popularItems = (try? await popular) ?? []
            let uniqueItems = (combined + popularItems).reduce(into: [Int: CafeQuickItem]()) { result, item in
                result[item.displayID] = result[item.displayID] ?? item
            }
            let newQuickItems = Array(uniqueItems.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }.prefix(12))
            guard !Task.isCancelled, id == activeShopID else { return }
            categories = newCategories
            menus = newMenus
            categoriesByShop[id] = newCategories
            menusByShop[id] = newMenus
            quickItems = newQuickItems
            loadedShopIDs.insert(id)
            quickItemsByShop[id] = newQuickItems
            ImagePipeline.shared.preload(
                newMenus.compactMap(\.thumbnailURL) + newQuickItems.compactMap(\.thumbnailURL),
                targetSize: 96
            )
            await store.refreshCafePlan(shopID: id, force: forceRefresh)
            _ = try? await store.refreshCart(shopID: id)
        } catch is CancellationError {
            return
        } catch {
            guard id == activeShopID else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func selectShop(_ id: Int) {
        guard id != activeShopID else { return }
        selectedCategoryID = nil
        categories = categoriesByShop[id] ?? []
        menus = menusByShop[id] ?? []
        quickItems = quickItemsByShop[id] ?? []
        searchText = ""
        errorMessage = nil
        shopID = id
        menuScrollPosition = ScrollPosition(idType: Int.self)
        store.selectShop(id)
    }

    private func loadAllShopMenus(force: Bool = false) async {
        guard !isLoadingAllShopMenus else { return }
        isLoadingAllShopMenus = true
        searchErrorMessage = nil
        defer {
            isLoadingAllShopMenus = false
            hasAttemptedAllShopMenus = true
        }

        let targets = store.cafeShops.filter { force || menusByShop[$0.id] == nil }
        let api = store.api
        let tasks = targets.map { shop in
            Task { @MainActor in
                    do {
                        let items = try await api.fetchCafeMenu(shopID: shop.id, forceRefresh: force)
                        return CafeShopMenuLoadResult(shopID: shop.id, shopName: shop.name, items: items)
                    } catch {
                        return CafeShopMenuLoadResult(shopID: shop.id, shopName: shop.name, items: nil)
                    }
            }
        }
        var results: [CafeShopMenuLoadResult] = []
        for task in tasks { results.append(await task.value) }
        guard !Task.isCancelled else { return }

        var failedShopNames: [String] = []
        for result in results {
            if let items = result.items {
                menusByShop[result.shopID] = items
                ImagePipeline.shared.preload(items.compactMap(\.thumbnailURL), targetSize: 96)
            } else {
                failedShopNames.append(result.shopName)
            }
        }
        if !failedShopNames.isEmpty {
            searchErrorMessage = "일부 매장 메뉴를 불러오지 못했습니다: \(failedShopNames.joined(separator: ", "))"
        }
    }

    private func quantity(for goodsID: Int?, shopID: Int? = nil) -> Int {
        guard let goodsID else { return 0 }
        return store.cart(for: shopID ?? activeShopID).items.first { $0.goodsID == goodsID }?.quantity ?? 0
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
            toggleFavorite: { store.toggleFavorite(shopID: shopID, item: item) },
            decrease: { mutate(item, shopID: shopID, delta: -1) },
            increase: { mutate(item, shopID: shopID, delta: 1) },
            openDetail: { openDetail(item, shopID: shopID) },
            quickOrder: { openQuickOrder(item, shopID: shopID) }
        )
        .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private var activeShopName: String {
        store.cafeShops.first(where: { $0.id == activeShopID })?.name ?? "매장 선택"
    }

    private func openDetail(_ item: CafeMenuItem, shopID: Int? = nil) {
        let destinationShopID = shopID ?? activeShopID
        store.selectShop(destinationShopID)
        router.push(.menu(shopID: destinationShopID, displayID: item.displayID), on: .cafe)
    }

    private func openQuickOrder(_ item: CafeMenuItem, shopID: Int) {
        store.selectShop(shopID)
        router.push(.quickOrder(shopID: shopID, displayID: item.displayID), on: .cafe)
    }

    private func mutate(_ menu: CafeMenuItem, shopID: Int? = nil, delta: Int) {
        guard let goodsID = menu.goodsID else { return }
        let destinationShopID = shopID ?? activeShopID
        actionError = nil
        Task {
            do {
                if let item = store.cart(for: destinationShopID).items.first(where: { $0.goodsID == goodsID }) {
                    try await store.setQuantity(shopID: destinationShopID, item: item, quantity: item.quantity + delta)
                } else if delta > 0 {
                    try await store.addToCart(shopID: destinationShopID, goodsID: goodsID)
                }
            } catch {
                withAnimation { actionError = error.localizedDescription }
            }
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
