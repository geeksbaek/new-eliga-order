import SwiftUI

struct OrderConfirmationView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    let shopID: Int
    let isQuickOrder: Bool

    @State private var reasons: [PaymentReason] = []
    @State private var selectedReasonID: Int?
    @State private var isLoading = true
    @State private var isPlacingOrder = false
    @State private var showsConfirmation = false
    @State private var errorMessage: String?
    @State private var orderSucceeded = false
    @State private var reviewedCart: Cart?

    private var cart: Cart { reviewedCart ?? store.cart(for: shopID) }

    var body: some View {
        Group {
            if isLoading {
                LoadingContentView(title: "주문 정보를 확인하는 중…")
            } else if let errorMessage, reviewedCart == nil {
                FailureContentView(message: errorMessage) {
                    Task { await load(forceRefresh: true) }
                }
            } else if cart.items.isEmpty {
                ContentUnavailableView("주문할 메뉴가 없습니다", systemImage: "bag.badge.minus")
            } else {
                Form {
                    if isQuickOrder {
                        Section {
                            Label("기존 장바구니와 분리된 바로 주문입니다.", systemImage: "bolt.fill")
                                .foregroundStyle(.primary)
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
                        Section { Label(errorMessage, systemImage: "exclamationmark.circle").foregroundStyle(.primary) }
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
        .navigationBarBackButtonHidden(isPlacingOrder)
        .confirmationDialog("주문을 확정할까요?", isPresented: $showsConfirmation, titleVisibility: .visible) {
            Button("주문하기") { placeOrder() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("\(cart.itemCount)개 메뉴를 \(AppFormat.won(cart.total))에 주문합니다.")
        }
        .task { await load() }
        .onDisappear {
            if isQuickOrder && !orderSucceeded && !isPlacingOrder {
                Task { try? await store.cancelQuickOrder() }
            }
        }
        .sensoryFeedback(.success, trigger: orderSucceeded)
    }

    private func load(forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        reviewedCart = nil
        reasons = []
        selectedReasonID = nil
        do {
            let refreshedCart = try await store.refreshCart(shopID: shopID)
            let refreshedReasons = try await store.api.fetchPaymentReasons(
                shopID: shopID,
                forceRefresh: forceRefresh
            )
            try Task.checkCancellation()
            reviewedCart = refreshedCart
            reasons = refreshedReasons
            selectedReasonID = refreshedReasons.first {
                $0.reason.range(of: "개인\\s*결제", options: .regularExpression) != nil
            }?.id ?? refreshedReasons.first?.id
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func placeOrder() {
        guard let selectedReasonID, !isPlacingOrder else { return }
        isPlacingOrder = true
        errorMessage = nil
        Task {
            do {
                guard let submittedCart = reviewedCart else { throw OrderValidationError.emptyCart }
                let orderID = try await store.placeOrder(
                    shopID: shopID,
                    reviewedCart: submittedCart,
                    paymentReasonID: selectedReasonID,
                    isQuickOrder: isQuickOrder
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
                if isQuickOrder {
                    do {
                        try await store.completeQuickOrder()
                    } catch {
                        store.globalError = "주문은 완료됐지만 기존 장바구니 복구가 지연되고 있습니다. 앱을 다시 열면 자동으로 복구합니다."
                    }
                } else {
                    _ = try? await store.refreshCart(shopID: shopID)
                }
                router.popToRoot(isQuickOrder ? .cafe : .cart)
                router.switchTo(.orders)
            } catch is CancellationError {
                isPlacingOrder = false
            } catch {
                errorMessage = error.localizedDescription
                isPlacingOrder = false
            }
        }
    }
}
