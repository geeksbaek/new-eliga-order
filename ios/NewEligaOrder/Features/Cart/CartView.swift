import SwiftUI

struct CartView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var loadingShopID: Int?
    @State private var errorMessage: String?
    @State private var feedbackToken = 0
    @State private var showsClearConfirmation = false
    /// Which edge the next shop's cart should slide in from, matching the
    /// swiped/chip-tapped direction (ascending-floor order).
    @State private var shopSwitchDirection: Edge = .trailing

    private var shopID: Int { store.selectedShopID ?? store.cafeShops.first?.id ?? 5 }
    private var cart: Cart { store.cart(for: shopID) }
    private var isLoading: Bool { loadingShopID == shopID }
    /// Lets the shop switcher badge shops that already have items, since
    /// otherwise the only way to find them is switching to each one.
    private var itemCountsByShop: [Int: Int] {
        Dictionary(uniqueKeysWithValues: store.cafeShops.map { ($0.id, store.cart(for: $0.id).itemCount) })
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if isLoading && cart.items.isEmpty {
                    LoadingContentView(title: "장바구니를 불러오는 중…")
                } else if let errorMessage, cart.items.isEmpty {
                    FailureContentView(message: errorMessage) {
                        Task { await refresh(shopID: shopID) }
                    }
                } else if cart.items.isEmpty {
                    ContentUnavailableView(
                        "장바구니가 비어 있습니다",
                        systemImage: "bag",
                        description: Text("카페 메뉴에서 음료를 담아 보세요.")
                            .foregroundStyle(.primary)
                    )
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
                    .refreshable { await refresh(shopID: shopID) }
                    .appScrollEdgeStyle()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(shopID)
            .transition(shopContentTransition)
            .clipped()
            // Covers every content state (loading/error/empty/list), not
            // just the populated cart, so swiping still steps to the
            // adjacent shop even when the current shop's cart is empty.
            .shopSwipeNavigation(
                shops: store.cafeShops,
                selectedShopID: shopID,
                selectShop: selectShop
            )

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
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
                    selectedShopID: shopID,
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
        .task(id: shopID) { await refresh(shopID: shopID) }
        .sensoryFeedback(.success, trigger: feedbackToken)
    }

    private func refresh(shopID requestedShopID: Int) async {
        loadingShopID = requestedShopID
        defer {
            if loadingShopID == requestedShopID { loadingShopID = nil }
        }
        do {
            _ = try await store.refreshCart(shopID: requestedShopID)
            guard !Task.isCancelled, requestedShopID == shopID else { return }
            errorMessage = nil
        }
        catch is CancellationError { return }
        catch {
            guard requestedShopID == shopID else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func selectShop(_ id: Int) {
        guard id != shopID else { return }
        updateShopSwitchDirection(to: id)
        store.selectShop(id)
        errorMessage = nil
    }

    /// Matches the content's slide direction to ascending-floor order, so a
    /// forward swipe/tap slides the new shop's cart in from the trailing
    /// edge and a backward one from the leading edge.
    private func updateShopSwitchDirection(to id: Int) {
        let sorted = CafeShopSwitcherPolicy.sortedByFloor(store.cafeShops)
        guard let currentIndex = sorted.firstIndex(where: { $0.id == shopID }),
              let nextIndex = sorted.firstIndex(where: { $0.id == id })
        else { return }
        shopSwitchDirection = nextIndex > currentIndex ? .trailing : .leading
    }

    private var shopContentTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: shopSwitchDirection).combined(with: .opacity),
            removal: .move(edge: shopSwitchDirection == .trailing ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func update(_ item: CartItem, delta: Int) {
        Task {
            do {
                try await store.adjustQuantity(shopID: shopID, itemID: item.id, delta: delta)
                feedbackToken += 1
            }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func delete(_ item: CartItem) {
        Task {
            do {
                try await store.deleteCartItem(shopID: shopID, itemID: item.id)
                feedbackToken += 1
            }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func clearCart() {
        Task {
            do {
                try await store.clearCart(shopID: shopID)
                feedbackToken += 1
            }
            catch { errorMessage = error.localizedDescription }
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
