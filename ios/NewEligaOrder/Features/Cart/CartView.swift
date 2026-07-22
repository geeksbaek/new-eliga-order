import SwiftUI

struct CartView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var shopID: Int?
    @State private var showsClearConfirmation = false
    @State private var actionError: String?
    @State private var clearFeedbackToken = 0
    /// See `scheduleStoreSync(to:)`.
    @State private var storeSyncTask: Task<Void, Never>?

    private var activeShopID: Int { shopID ?? store.selectedShopID ?? store.cafeShops.first?.id ?? 5 }
    private var cart: Cart { store.cart(for: activeShopID) }
    /// Ascending-floor order, regardless of the raw API order — also the
    /// order the shop `TabView` pages through.
    private var sortedShops: [Shop] { CafeShopSwitcherPolicy.sortedByFloor(store.cafeShops) }
    /// Lets the shop switcher badge shops that already have items, since
    /// otherwise the only way to find them is switching to each one.
    private var itemCountsByShop: [Int: Int] {
        Dictionary(uniqueKeysWithValues: store.cafeShops.map { ($0.id, store.cart(for: $0.id).itemCount) })
    }
    private var activeShopIDBinding: Binding<Int> {
        Binding(get: { activeShopID }, set: { selectShop($0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            // A native paged `TabView` tracks the finger 1:1 during the
            // drag — the adjacent shop's cart slides in right alongside it,
            // matching the same live-motion paging CafeView uses.
            TabView(selection: activeShopIDBinding) {
                ForEach(sortedShops) { shop in
                    CartShopPageView(shopID: shop.id, onError: { actionError = $0 })
                        .tag(shop.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // Nothing to pop back to at this tab's root — freeing the left
            // edge from the system back-swipe lets a leftward drag that
            // starts near it still page backward. Re-enabled whenever a
            // detail screen is pushed, so back-swipe still works there.
            .disablesInteractivePopGesture(while: router.cartPath.isEmpty)

            if let actionError {
                Label(actionError, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .padding()
            }
        }
        .navigationTitle("장바구니")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            // Same header row as CafeView, with a clear-cart button in the
            // same trailing spot CafeView uses for search. The order-confirm
            // action lives inline at the end of the cart list instead of
            // floating here, so it reads as part of the content it's
            // confirming rather than a bar stuck to the screen edge.
            if store.cafeShops.count > 1 || !cart.items.isEmpty {
                CafeShopHeaderBar(
                    shops: store.cafeShops,
                    selectedShopID: activeShopID,
                    selectShop: selectShop,
                    trailingAccessory: cart.items.isEmpty ? nil : CafeShopHeaderBar.TrailingAccessory(
                        systemImage: "trash",
                        accessibilityLabel: "장바구니 비우기",
                        accessibilityIdentifier: "cart.clear.accessory",
                        isDestructive: true,
                        action: { showsClearConfirmation = true }
                    ),
                    itemCounts: itemCountsByShop
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }
        }
        .confirmationDialog(
            "장바구니를 비울까요?",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("비우기", role: .destructive) { clearCart() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("\(cart.itemCount)개 메뉴가 모두 삭제됩니다.")
        }
        .sensoryFeedback(.success, trigger: clearFeedbackToken)
        .onChange(of: store.selectedShopID) { _, selectedShopID in
            guard
                let selectedShopID,
                store.cafeShops.contains(where: { $0.id == selectedShopID })
            else { return }
            selectShop(selectedShopID)
        }
    }

    private func selectShop(_ id: Int) {
        guard id != activeShopID else { return }
        shopID = id
        scheduleStoreSync(to: id)
    }

    /// Debounces the shared-store sync — and the side effects that ride
    /// along with it (a cross-tab `onChange(of: store.selectedShopID)`
    /// cascade in `CafeView`, a synchronous `UserDefaults` write, a
    /// selection haptic) — so it only fires once a swipe has actually
    /// settled. `TabView(.page)` updates its `selection` binding live on
    /// every page crossing during the drag itself, not just once at the
    /// end, so calling `store.selectShop` directly from that binding's
    /// setter ran all of that side-effect work mid-gesture, once per shop
    /// the user's finger passed over.
    private func scheduleStoreSync(to id: Int) {
        storeSyncTask?.cancel()
        storeSyncTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            store.selectShop(id)
        }
    }

    private func clearCart() {
        Task {
            do {
                try await store.clearCart(shopID: activeShopID)
                clearFeedbackToken += 1
            }
            catch { actionError = error.localizedDescription }
        }
    }
}

/// One shop's full cart page — loading/error/empty states and the item
/// list — owning its own state so the enclosing `TabView(.page)` can keep
/// every shop's page alive and page between them with live, finger-tracked
/// motion.
private struct CartShopPageView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    let shopID: Int
    let onError: (String) -> Void

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var feedbackToken = 0
    @State private var hasLoadedOnce = false

    private var cart: Cart { store.cart(for: shopID) }

    var body: some View {
        // Every branch gets the same explicit full-size frame — without it,
        // `ContentUnavailableView`/`LoadingContentView` size to their own
        // content instead of filling the page like `List` does, so a
        // page's overall height could change out from under `TabView(.page)`
        // right as its data resolves. If that happens while the user is
        // mid-swipe, the paging scroll view's animation can lock up between
        // two pages instead of settling normally.
        Group {
            if isLoading && cart.items.isEmpty {
                LoadingContentView(title: "장바구니를 불러오는 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, cart.items.isEmpty {
                FailureContentView(message: errorMessage) {
                    Task { await refresh() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if cart.items.isEmpty {
                ContentUnavailableView(
                    "장바구니가 비어 있습니다",
                    systemImage: "bag",
                    description: Text("카페 메뉴에서 음료를 담아 보세요.")
                        .foregroundStyle(.primary)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(cart.items) { item in
                        CartItemRow(item: item) { delta in
                            update(item, delta: delta)
                        }
                        .contextMenu {
                            Button("삭제", systemImage: "trash", role: .destructive) { delete(item) }
                        }
                    }
                    Section {
                        LabeledContent("총 수량", value: "\(cart.itemCount)개")
                        LabeledContent("결제 금액") { PriceText(amount: cart.total) }
                    }
                    Section {
                        AppPrimaryActionButton(
                            title: "주문 확인 · \(AppFormat.won(cart.total))",
                            systemImage: "checkmark.circle.fill"
                        ) {
                            router.push(.orderConfirmation(shopID: shopID, isQuickOrder: false), on: .cart)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await refresh() }
                .appScrollEdgeStyle()
            }
        }
        .task {
            guard !hasLoadedOnce else { return }
            // A brief, cancellable pause before starting the load — see
            // `CafeShopPageView`'s identical comment for why: `TabView(.page)`
            // starts this task while the user's finger may still be
            // dragging across this page, and letting the load finish (and
            // this page's `List` relayout) mid-gesture can stall the native
            // paging animation. A page just scrolled past cancels here
            // before ever loading.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, !hasLoadedOnce else { return }
            hasLoadedOnce = true
            await refresh()
        }
        .sensoryFeedback(.success, trigger: feedbackToken)
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await store.refreshCart(shopID: shopID)
            guard !Task.isCancelled else { return }
            errorMessage = nil
        }
        catch is CancellationError { return }
        catch {
            errorMessage = error.localizedDescription
        }
    }

    private func update(_ item: CartItem, delta: Int) {
        Task {
            do {
                try await store.adjustQuantity(shopID: shopID, itemID: item.id, delta: delta)
                feedbackToken += 1
            }
            catch { onError(error.localizedDescription) }
        }
    }

    private func delete(_ item: CartItem) {
        Task {
            do {
                try await store.deleteCartItem(shopID: shopID, itemID: item.id)
                feedbackToken += 1
            }
            catch { onError(error.localizedDescription) }
        }
    }
}

private struct CartItemRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let item: CartItem
    let adjustQuantity: (Int) -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    itemInformation
                    HStack {
                        Spacer()
                        quantityControl
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    itemInformation
                    Spacer(minLength: 6)
                    quantityControl
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var itemInformation: some View {
        HStack(alignment: .top, spacing: 10) {
            RemoteThumbnail(url: item.thumbnailURL)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(item.options, id: \.self) { option in
                    Text("\(option.option): \(option.value)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PriceText(amount: item.lineTotal)
            }
        }
    }

    private var quantityControl: some View {
        HStack(spacing: 0) {
            Button("수량 감소", systemImage: "minus") { adjustQuantity(-1) }
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
            Text("\(item.quantity)")
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(minWidth: 28)
                .accessibilityLabel("수량 \(item.quantity)개")
            Button("수량 증가", systemImage: "plus") { adjustQuantity(1) }
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
                .disabled(item.quantity >= 20)
        }
        .buttonStyle(.borderless)
        .background(.quaternary, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.name) 수량 \(item.quantity)개")
    }
}
