import SwiftUI

struct OrderConfirmationView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    let isQuickOrder: Bool

    @State private var reasons: [PaymentReason] = []
    @State private var selectedReasonID: Int?
    @State private var isLoading = true
    @State private var isPlacingOrder = false
    @State private var showsConfirmation = false
    @State private var errorMessage: String?
    @State private var orderSucceeded = false

    private var shopID: Int { store.selectedShopID ?? 5 }
    private var cart: Cart { store.cart(for: shopID) }

    var body: some View {
        Group {
            if isLoading {
                LoadingContentView(title: "주문 정보를 확인하는 중…")
            } else if cart.items.isEmpty {
                ContentUnavailableView("주문할 메뉴가 없습니다", systemImage: "bag.badge.minus")
            } else {
                Form {
                    if isQuickOrder {
                        Section {
                            Label("기존 장바구니와 분리된 바로 주문입니다.", systemImage: "bolt.fill")
                                .foregroundStyle(.orange)
                        }
                    }

                    Section("주문 메뉴") {
                        ForEach(cart.items) { item in
                            LabeledContent {
                                PriceText(amount: item.lineTotal)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(item.name)
                                    Text("\(item.quantity)개").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Section("결제 사유") {
                        Picker("결제 사유", selection: $selectedReasonID) {
                            Text("선택").tag(nil as Int?)
                            ForEach(reasons) { Text($0.reason).tag(Optional($0.id)) }
                        }
                    }

                    Section("결제") {
                        LabeledContent("총 결제 금액") { PriceText(amount: cart.total) }
                    }

                    if let errorMessage {
                        Section { Label(errorMessage, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    AppBottomActionBar {
                        AppPrimaryActionButton(
                            title: isPlacingOrder ? "주문 중…" : "\(AppFormat.won(cart.total)) 주문하기",
                            systemImage: "checkmark.seal.fill",
                            isWorking: isPlacingOrder
                        ) {
                            showsConfirmation = true
                        }
                        .disabled(selectedReasonID == nil || isPlacingOrder)
                    }
                }
            }
        }
        .navigationTitle(isQuickOrder ? "바로 주문 확인" : "주문 확인")
        .confirmationDialog("주문을 확정할까요?", isPresented: $showsConfirmation, titleVisibility: .visible) {
            Button("주문하기") { placeOrder() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("\(cart.itemCount)개 메뉴를 \(AppFormat.won(cart.total))에 주문합니다.")
        }
        .task { await load() }
        .onDisappear {
            if isQuickOrder && !orderSucceeded {
                Task { await store.cancelQuickOrder() }
            }
        }
        .sensoryFeedback(.success, trigger: orderSucceeded)
    }

    private func load() async {
        isLoading = true
        do {
            _ = try await store.refreshCart(shopID: shopID)
            reasons = try await store.api.fetchPaymentReasons(shopID: shopID)
            selectedReasonID = reasons.first { $0.reason.range(of: "개인\\s*결제", options: .regularExpression) != nil }?.id
                ?? reasons.first?.id
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    private func placeOrder() {
        guard let selectedReasonID, !isPlacingOrder else { return }
        isPlacingOrder = true
        errorMessage = nil
        Task {
            do {
                let submittedCart = store.cart(for: shopID)
                let orderID = try await store.api.placeOrder(
                    shopID: shopID,
                    cart: submittedCart,
                    paymentReasonID: selectedReasonID
                )
                if let orderID {
                    let shopName = store.shops.first(where: { $0.id == shopID })?.name ?? ""
                    await OrderLiveActivityManager.shared.start(
                        orderID: orderID,
                        shopName: shopName,
                        cart: submittedCart
                    )
                    await OrderMonitoringCoordinator.shared.track(
                        orderID: orderID,
                        shopName: shopName,
                        using: store.api
                    )
                }
                orderSucceeded = true
                store.completeQuickOrder()
                _ = try? await store.refreshCart(shopID: shopID)
                router.popToRoot(isQuickOrder ? .cafe : .cart)
                router.switchTo(.orders)
            } catch {
                errorMessage = error.localizedDescription
                isPlacingOrder = false
            }
        }
    }
}
