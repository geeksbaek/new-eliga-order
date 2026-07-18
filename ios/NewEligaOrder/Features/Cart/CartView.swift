import SwiftUI

struct CartView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var feedbackToken = 0

    private var shopID: Int { store.selectedShopID ?? store.cafeShops.first?.id ?? 5 }
    private var cart: Cart { store.cart(for: shopID) }

    var body: some View {
        VStack(spacing: 0) {
            if !store.cafeShops.isEmpty {
                ScrollView(.horizontal) {
                    AppGlassGroup(spacing: 10) {
                        HStack {
                            ForEach(store.cafeShops) { shop in
                                SelectionChip(title: shop.name, isSelected: shop.id == shopID) {
                                    selectShop(shop.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .scrollIndicators(.hidden)
                .padding(.vertical, 8)
            }

            if isLoading && cart.items.isEmpty {
                LoadingContentView(title: "장바구니를 불러오는 중…")
            } else if cart.items.isEmpty {
                ContentUnavailableView(
                    "장바구니가 비어 있습니다",
                    systemImage: "bag",
                    description: Text("카페 메뉴에서 음료를 담아 보세요.")
                )
            } else {
                List {
                    ForEach(cart.items) { item in
                        CartItemRow(item: item) { quantity in
                            update(item, quantity: quantity)
                        }
                        .swipeActions {
                            Button("삭제", role: .destructive) { delete(item) }
                        }
                    }
                    Section {
                        LabeledContent("총 수량", value: "\(cart.itemCount)개")
                        LabeledContent("결제 금액") { PriceText(amount: cart.total) }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await refresh() }
                .appScrollEdgeStyle()
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding()
            }
        }
        .navigationTitle("장바구니")
        .safeAreaInset(edge: .bottom) {
            if !cart.items.isEmpty {
                AppBottomActionBar {
                    AppPrimaryActionButton(
                        title: "주문 확인 · \(AppFormat.won(cart.total))",
                        systemImage: "checkmark.circle.fill"
                    ) {
                        router.push(.orderConfirmation(isQuickOrder: false), on: .cart)
                    }
                }
            }
        }
        .task { await refresh() }
        .sensoryFeedback(.success, trigger: feedbackToken)
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do { _ = try await store.refreshCart(shopID: shopID); errorMessage = nil }
        catch is CancellationError { return }
        catch { errorMessage = error.localizedDescription }
    }

    private func selectShop(_ id: Int) {
        guard id != shopID else { return }
        store.selectShop(id)
        errorMessage = nil
        Task { await refresh() }
    }

    private func update(_ item: CartItem, quantity: Int) {
        Task {
            do {
                try await store.setQuantity(shopID: shopID, item: item, quantity: quantity)
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
}

private struct CartItemRow: View {
    let item: CartItem
    let updateQuantity: (Int) -> Void

    var body: some View {
        HStack(alignment: .top) {
            RemoteThumbnail(url: item.thumbnailURL)
            VStack(alignment: .leading) {
                Text(item.name).font(.headline)
                ForEach(item.options, id: \.self) { option in
                    Text("\(option.option): \(option.value)").font(.caption).foregroundStyle(.secondary)
                }
                PriceText(amount: item.lineTotal)
            }
            Spacer()
            HStack {
                Button("수량 감소", systemImage: "minus") { updateQuantity(item.quantity - 1) }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                Text("\(item.quantity)")
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(minWidth: 22)
                Button("수량 증가", systemImage: "plus") { updateQuantity(item.quantity + 1) }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(item.quantity >= 20)
            }
            .buttonStyle(.borderless)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(item.name) 수량 \(item.quantity)개")
        }
        .accessibilityElement(children: .contain)
    }
}
