import SwiftUI

struct CafeView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    let transitionNamespace: Namespace.ID
    private let searchHistoryStore = CafeSearchHistoryStore()

    @State private var shopID: Int?
    @State private var categories: [CafeCategory] = []
    @State private var selectedCategoryID: Int?
    @State private var menus: [CafeMenuItem] = []
    @State private var quickItems: [CafeQuickItem] = []
    @State private var loadingShopID: Int?
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var searchText = ""
    @State private var searchHistory: [String] = []
    @State private var menusByShop: [Int: [CafeMenuItem]] = [:]
    @State private var categoriesByShop: [Int: [CafeCategory]] = [:]
    @State private var quickItemsByShop: [Int: [CafeQuickItem]] = [:]
    @State private var isLoadingAllShopMenus = false
    @State private var searchErrorMessage: String?
    @State private var hasAttemptedAllShopMenus = false
    @State private var allShopMenuLoadGeneration = 0
    @State private var loadedShopIDs: Set<Int> = []
    @State private var menuScrollPosition = ScrollPosition(idType: Int.self)
    @State private var menuScrollPositionsByShop: [Int: ScrollPosition] = [:]

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
                if !searchHistory.isEmpty {
                    Section("최근 검색") {
                        ForEach(searchHistory, id: \.self) { query in
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isSearchActive, store.cafeShops.count > 1 {
                CafeShopModeSwitcher(
                    shops: store.cafeShops,
                    selectedShopID: activeShopID,
                    selectShop: selectShop
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if let actionError {
                Text(actionError)
                    .font(.callout)
                    .padding()
                    .appGlassSurface(cornerRadius: 22, tint: .red)
                    .padding()
                    .padding(.bottom, !isSearchActive && store.cafeShops.count > 1 ? 56 : 0)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .task(id: activeShopID) {
            guard !loadedShopIDs.contains(activeShopID) else { return }
            await load(shopID: activeShopID, replacingContent: true)
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
        .onDisappear {
            recordCurrentSearch()
        }
        .sensoryFeedback(.selection, trigger: selectedCategoryID)
        .animation(.snappy, value: isSearchActive)
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
            CafeOrderAvailabilityCard(closure: closure, shopName: activeShopName)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
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
                        menuRow(item, shopID: activeShopID)
                    }
                }
                .listSectionSeparator(.hidden)
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
        menuScrollPositionsByShop[activeShopID] = menuScrollPosition
        selectedCategoryID = nil
        categories = categoriesByShop[id] ?? []
        menus = menusByShop[id] ?? []
        quickItems = quickItemsByShop[id] ?? []
        searchText = ""
        errorMessage = nil
        shopID = id
        menuScrollPosition = menuScrollPositionsByShop[id] ?? ScrollPosition(idType: Int.self)
        store.selectShop(id)
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

        let targets = store.cafeShops.filter { force || menusByShop[$0.id] == nil }
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
        recordCurrentSearch()
        let destinationShopID = shopID ?? activeShopID
        store.selectShop(destinationShopID)
        router.push(.menu(shopID: destinationShopID, displayID: item.displayID), on: .cafe)
    }

    private func openQuickOrder(_ item: CafeMenuItem, shopID: Int) {
        recordCurrentSearch()
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

    private func mutate(_ menu: CafeMenuItem, shopID: Int? = nil, delta: Int) {
        guard let goodsID = menu.goodsID else { return }
        let destinationShopID = shopID ?? activeShopID
        actionError = nil
        Task {
            do {
                try await store.adjustGoodsQuantity(
                    shopID: destinationShopID,
                    goodsID: goodsID,
                    delta: delta
                )
            } catch {
                withAnimation { actionError = error.localizedDescription }
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
