import SwiftUI

struct MenuDetailView: View {
    private enum PendingAction {
        case addToCart
        case quickOrder
    }

    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    let shopID: Int
    let displayID: Int
    let transitionNamespace: Namespace.ID
    private let optionSelectionStore = CafeMenuOptionSelectionStore()

    @State private var detail: MenuDetail?
    @State private var selectedVariantID: Int?
    @State private var selectedMenus: [Int: Set<Int>] = [:]
    @State private var quantity = 1
    @State private var isLoading = true
    @State private var pendingAction: PendingAction?
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var actionTask: Task<Void, Never>?

    private var variant: GoodsVariant? {
        detail?.variants.first { $0.id == selectedVariantID } ?? detail?.variants.first
    }

    private var selectedOptions: [SelectedOption] {
        selectedMenus
            .map { SelectedOption(optionID: $0.key, menuIDs: Array($0.value).sorted()) }
            .sorted { $0.optionID < $1.optionID }
    }

    private var orderState: CafeOrderState {
        CafeRules.state(for: store.cafePlansByShop[shopID] ?? nil)
    }

    private var total: Int {
        guard let variant else { return 0 }
        let optionTotal = variant.options.flatMap(\.menus)
            .filter { menu in selectedMenus.values.contains { $0.contains(menu.id) } }
            .reduce(0) { $0 + $1.price }
        return (variant.price + optionTotal) * quantity
    }

    private var isSubmitting: Bool { pendingAction != nil }

    var body: some View {
        Group {
            if isLoading {
                LoadingContentView(title: "메뉴 상세를 불러오는 중…")
            } else if let errorMessage, detail == nil {
                FailureContentView(message: errorMessage) { Task { await load(forceRefresh: true) } }
            } else if let detail, let variant {
                AppMenuDetailScrollView {
                    menuHeader(detail: detail, variant: variant)
                    availabilityNotice

                    if detail.variants.count > 1 {
                        AppMenuDetailSection(title: "온도 / 종류", systemImage: "thermometer.medium") {
                            VStack(spacing: 8) {
                                ForEach(detail.variants) { candidate in
                                    variantButton(candidate)
                                }
                            }
                        }
                    }

                    ForEach(variant.options) { option in
                        optionSection(option)
                    }

                    AppMenuDetailSection(title: "주문 수량", systemImage: "number") {
                        MenuQuantitySelector(quantity: $quantity, total: total)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    AppBottomActionBar {
                        VStack(spacing: 10) {
                            actionStatus(variant: variant)
                            actionButtons(variant: variant)
                        }
                        .frame(maxWidth: AppDesign.contentMaxWidth)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("cafe.menu-detail.actions")
                    }
                }
            } else {
                ContentUnavailableView("메뉴 정보가 없습니다", systemImage: "cup.and.saucer")
            }
        }
        .navigationTitle(variant?.name ?? "메뉴")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onDisappear { actionTask?.cancel() }
        .task(id: successMessage) {
            guard successMessage != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation { successMessage = nil }
        }
        .sensoryFeedback(.success, trigger: successMessage)
    }

    private func actionButtons(variant: GoodsVariant) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                addToCartButton(variant: variant)
                    .frame(minWidth: 132, maxWidth: 148)
                quickOrderButton(variant: variant)
                    .frame(minWidth: 168, maxWidth: .infinity)
            }

            VStack(spacing: 10) {
                quickOrderButton(variant: variant)
                addToCartButton(variant: variant)
            }
        }
    }

    private func addToCartButton(variant: GoodsVariant) -> some View {
        AppSecondaryActionButton(
            title: "담기",
            systemImage: "bag.badge.plus",
            isWorking: pendingAction == .addToCart
        ) {
            add(.addToCart)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .accessibilityLabel("장바구니에 담기")
        .disabled(isSubmitting || variant.isSoldOut || !orderState.isOrderable)
    }

    private func quickOrderButton(variant: GoodsVariant) -> some View {
        AppPrimaryActionButton(
            title: "바로 주문",
            systemImage: "bolt.fill",
            isWorking: pendingAction == .quickOrder
        ) {
            add(.quickOrder)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .disabled(isSubmitting || variant.isSoldOut || !orderState.isOrderable)
    }

    @ViewBuilder
    private func actionStatus(variant: GoodsVariant) -> some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.circle")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
        } else if let successMessage {
            Label(successMessage, systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
        } else if variant.isSoldOut {
            actionStatusLabel("품절된 메뉴입니다", systemImage: "xmark.circle")
        }
    }

    @ViewBuilder
    private var availabilityNotice: some View {
        switch orderState {
        case .checking:
            CafeOrderCheckingCard()
        case .closed(let closure):
            CafeOrderAvailabilityCard(closure: closure, shopName: shopName)
        case .open:
            EmptyView()
        }
    }

    private var shopName: String {
        store.cafeShops.first(where: { $0.id == shopID })?.name ?? "선택한 매장"
    }

    private func actionStatusLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func menuHeader(detail: MenuDetail, variant: GoodsVariant) -> some View {
        AppMenuDetailHeader(
            imageURL: variant.thumbnailURL ?? detail.thumbnailURL,
            imageAccessibilityLabel: "\(variant.name) 메뉴 사진",
            placeholderSystemImage: "cup.and.saucer",
            isUnavailable: variant.isSoldOut
        ) {
            menuSummary(detail: detail, variant: variant)
        }
    }

    private func menuSummary(detail: MenuDetail, variant: GoodsVariant) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label = detail.label, !label.isEmpty {
                MenuLabelBadge(text: label, size: .regular)
            }
            Text(variant.name)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
            if let description = variant.description, !description.isEmpty {
                Text(AppFormat.minutePrecision(description))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PriceText(amount: variant.price)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func optionSection(_ option: GoodsOption) -> some View {
        AppMenuDetailSection(title: option.name, systemImage: "checklist") {
            if option.allowsMultipleSelection {
                ForEach(option.menus) { menu in
                    Toggle(isOn: optionBinding(optionID: option.id, menuID: menu.id)) {
                        HStack {
                            Text(menu.name)
                            Spacer()
                            if menu.price > 0 {
                                Text("+\(AppFormat.won(menu.price))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(minHeight: 44)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(option.menus) { menu in
                        let isSelected = selectedMenus[option.id]?.contains(menu.id) == true
                        Button {
                            selectedMenus[option.id] = [menu.id]
                            persistSelection()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                    .font(.title3)
                                Text(menu.name)
                                    .font(.body.weight(isSelected ? .semibold : .regular))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if menu.price > 0 {
                                    Text("+\(AppFormat.won(menu.price))")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 52)
                            .background(
                                isSelected ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(isSelected ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityLabel(menu.name)
                        .accessibilityValue(menu.price > 0 ? "추가 금액 \(AppFormat.won(menu.price))" : "추가 금액 없음")
                    }
                }
            }
        }
    }

    private func variantButton(_ candidate: GoodsVariant) -> some View {
        let isSelected = candidate.id == (selectedVariantID ?? variant?.id)
        let title = candidate.displayName.isEmpty ? candidate.name : candidate.displayName
        return Button {
            selectVariant(candidate.id)
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    variantSelectionIcon(isSelected: isSelected)
                    Text(title)
                        .font(.body.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    variantPrice(candidate)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        variantSelectionIcon(isSelected: isSelected)
                        Text(title)
                            .font(.body.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(.primary)
                    }
                    variantPrice(candidate)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(candidate.isSoldOut)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(candidate.isSoldOut ? "\(title), 품절" : title)
        .accessibilityValue(AppFormat.won(candidate.price))
    }

    private func variantSelectionIcon(isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .font(.title3)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func variantPrice(_ candidate: GoodsVariant) -> some View {
        if candidate.isSoldOut {
            Text("품절")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        } else {
            PriceText(amount: candidate.price)
        }
    }

    private func load(forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            async let loadedPlan: Void = store.refreshCafePlan(shopID: shopID, force: forceRefresh)
            let loaded = try await store.api.fetchMenuDetail(displayID: displayID, forceRefresh: forceRefresh)
            await loadedPlan
            guard !Task.isCancelled else { return }
            guard loaded.shopID == nil || loaded.shopID == shopID else {
                throw MenuDetailError.invalidShop
            }
            detail = loaded
            ImagePipeline.shared.preload(
                ([loaded.thumbnailURL] + loaded.variants.map(\.thumbnailURL)).compactMap { $0 },
                targetSize: 180,
                limit: 8
            )
            if let restored = optionSelectionStore.restore(
                accountID: store.userIDHint,
                shopID: shopID,
                displayID: displayID,
                detail: loaded
            ) {
                selectedVariantID = restored.variantID
                selectedMenus = restored.selectedMenus
            } else if let first = loaded.variants.first {
                selectVariant(first.id)
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectVariant(_ id: Int) {
        selectedVariantID = id
        selectedMenus = [:]
        guard let variant = detail?.variants.first(where: { $0.id == id }) else { return }
        for option in variant.options where !option.allowsMultipleSelection {
            if let first = option.menus.first { selectedMenus[option.id] = [first.id] }
        }
        persistSelection()
    }

    private func optionBinding(optionID: Int, menuID: Int) -> Binding<Bool> {
        Binding(
            get: { selectedMenus[optionID]?.contains(menuID) == true },
            set: { selected in
                var values = selectedMenus[optionID] ?? []
                if selected { values.insert(menuID) } else { values.remove(menuID) }
                selectedMenus[optionID] = values
                persistSelection()
            }
        )
    }

    private func persistSelection() {
        guard let detail, let selectedVariantID else { return }
        optionSelectionStore.save(
            accountID: store.userIDHint,
            shopID: shopID,
            displayID: displayID,
            detail: detail,
            variantID: selectedVariantID,
            selectedMenus: selectedMenus
        )
    }

    private func add(_ action: PendingAction) {
        guard let variant, !isSubmitting else { return }
        pendingAction = action
        errorMessage = nil
        actionTask?.cancel()
        actionTask = Task {
            defer { pendingAction = nil }
            do {
                if action == .quickOrder {
                    try await store.beginQuickOrder(
                        shopID: shopID,
                        goodsID: variant.id,
                        quantity: quantity,
                        options: selectedOptions
                    )
                    try Task.checkCancellation()
                    router.push(.orderConfirmation(shopID: shopID, isQuickOrder: true), on: .cafe)
                } else {
                    try await store.addToCart(
                        shopID: shopID,
                        goodsID: variant.id,
                        quantity: quantity,
                        options: selectedOptions
                    )
                    withAnimation { successMessage = "장바구니에 담았습니다" }
                }
            } catch is CancellationError {
                if action == .quickOrder { try? await store.cancelQuickOrder() }
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private enum MenuDetailError: LocalizedError {
    case invalidShop

    var errorDescription: String? {
        "선택한 매장과 메뉴 정보가 일치하지 않습니다. 메뉴 목록에서 다시 선택해 주세요."
    }
}

private struct MenuQuantitySelector: View {
    @Binding var quantity: Int
    let total: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                quantityControl
                Spacer(minLength: 12)
                totalLabel
            }
            VStack(alignment: .leading, spacing: 14) {
                quantityControl
                totalLabel
            }
        }
    }

    private var quantityControl: some View {
        HStack(spacing: 4) {
            quantityButton(
                title: "수량 감소",
                systemImage: "minus",
                isDisabled: quantity <= 1
            ) {
                quantity = max(1, quantity - 1)
            }

            Text("\(quantity)")
                .font(.title3.monospacedDigit().weight(.semibold))
                .contentTransition(.numericText())
                .frame(minWidth: 38)
                .accessibilityLabel("수량 \(quantity)개")

            quantityButton(
                title: "수량 증가",
                systemImage: "plus",
                isDisabled: quantity >= 20
            ) {
                quantity = min(20, quantity + 1)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func quantityButton(
        title: String,
        systemImage: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isDisabled ? Color.secondary.opacity(0.45) : Color.accentColor)
        .background(Color(.tertiarySystemFill), in: Circle())
        .disabled(isDisabled)
        .accessibilityLabel(title)
    }

    private var totalLabel: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("예상 결제 금액")
                .font(.caption)
                .foregroundStyle(.secondary)
            PriceText(amount: total)
                .font(.title3)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
struct CafeMenuDetailQuantityFixtureView: View {
    @State private var quantity = 2

    var body: some View {
        NavigationStack {
            AppMenuDetailScrollView {
                AppMenuDetailSection(title: "주문 수량", systemImage: "number") {
                    MenuQuantitySelector(quantity: $quantity, total: quantity * 4_500)
                }
            }
            .navigationTitle("시그니처 라떼")
        }
    }
}

struct CafeMenuDetailHolidayFixtureView: View {
    private let closure = CafeOrderClosure(
        reason: .holiday,
        title: "오늘은 휴무예요",
        detail: "선택한 매장은 오늘 운영하지 않아요.",
        schedule: "다음 영업 · 월요일 09:00–19:00"
    )

    var body: some View {
        NavigationStack {
            AppMenuDetailScrollView {
                AppMenuDetailHeader(
                    imageURL: nil,
                    imageAccessibilityLabel: "시그니처 라떼 메뉴 사진",
                    placeholderSystemImage: "cup.and.saucer"
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("시그니처 라떼")
                            .font(.title2.bold())
                        Text("부드러운 우유와 에스프레소")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        PriceText(amount: 4_500)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                CafeOrderAvailabilityCard(closure: closure, shopName: "엘리가 카페")

                AppMenuDetailSection(title: "주문 수량", systemImage: "number") {
                    Text("휴무일에는 주문 수량을 변경할 수 없습니다.")
                        .foregroundStyle(.secondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                AppBottomActionBar {
                    HStack(spacing: 12) {
                        AppSecondaryActionButton(title: "담기", systemImage: "bag.badge.plus") {}
                            .disabled(true)
                        AppPrimaryActionButton(title: "바로 주문", systemImage: "bolt.fill") {}
                            .disabled(true)
                    }
                    .frame(maxWidth: AppDesign.contentMaxWidth)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("cafe.menu-detail.actions")
                }
            }
            .navigationTitle("시그니처 라떼")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif
