import SwiftUI

struct CartView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var loadingShopID: Int?
    @State private var errorMessage: String?
    @State private var feedbackToken = 0

    private var shopID: Int { store.selectedShopID ?? store.cafeShops.first?.id ?? 5 }
    private var cart: Cart { store.cart(for: shopID) }
    private var isLoading: Bool { loadingShopID == shopID }

    var body: some View {
        VStack(spacing: 0) {
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
                .refreshable { await refresh(shopID: shopID) }
                .appScrollEdgeStyle()
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .padding()
            }
        }
        .navigationTitle("장바구니")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                CafeShopPickerMenu(
                    shops: store.cafeShops,
                    selectedShopID: shopID,
                    selectShop: selectShop
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !cart.items.isEmpty {
                AppBottomActionBar {
                    AppPrimaryActionButton(
                        title: "주문 확인 · \(AppFormat.won(cart.total))",
                        systemImage: "checkmark.circle.fill"
                    ) {
                        router.push(.orderConfirmation(shopID: shopID, isQuickOrder: false), on: .cart)
                    }
                }
            }
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
        store.selectShop(id)
        errorMessage = nil
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
