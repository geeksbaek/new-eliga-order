import SwiftUI

struct QuickOrderLaunchView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    let shopID: Int
    let displayID: Int

    @State private var errorMessage: String?
    @State private var attempt = 0

    var body: some View {
        Group {
            if let errorMessage {
                ContentUnavailableView {
                    Label("바로 주문을 준비하지 못했습니다", systemImage: "bolt.trianglebadge.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("다시 시도") { attempt += 1 }
                    Button("메뉴에서 확인") {
                        router.switchTo(.cafe, route: .menu(shopID: shopID, displayID: displayID))
                    }
                }
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("즐겨찾기 메뉴를 준비하는 중…")
                        .font(.headline)
                    Text("기존 장바구니는 주문 확인이 끝날 때까지 안전하게 보관됩니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("바로 주문")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: attempt) { await prepareOrder() }
    }

    private func prepareOrder() async {
        errorMessage = nil
        do {
            async let loadedPlan: Void = store.refreshCafePlan(shopID: shopID)
            let detail = try await store.api.fetchMenuDetail(displayID: displayID)
            await loadedPlan

            guard CafeRules.state(for: store.cafePlansByShop[shopID] ?? nil).isOrderable else {
                throw QuickOrderLaunchError.shopClosed
            }
            guard let variant = detail.variants.first(where: { !$0.isSoldOut }) else {
                throw QuickOrderLaunchError.soldOut
            }
            let options = variant.options.compactMap { option -> SelectedOption? in
                guard !option.allowsMultipleSelection, let first = option.menus.first else { return nil }
                return SelectedOption(optionID: option.id, menuIDs: [first.id])
            }
            try await store.beginQuickOrder(
                shopID: shopID,
                goodsID: variant.id,
                quantity: 1,
                options: options
            )
            guard !Task.isCancelled else { return }
            router.switchTo(.cafe, route: .orderConfirmation(isQuickOrder: true))
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum QuickOrderLaunchError: LocalizedError {
    case shopClosed
    case soldOut

    var errorDescription: String? {
        switch self {
        case .shopClosed: "지금은 이 카페에서 주문할 수 없습니다."
        case .soldOut: "현재 주문 가능한 메뉴 옵션이 없습니다."
        }
    }
}
