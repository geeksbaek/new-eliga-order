import SwiftUI
import UIKit

struct RemoteThumbnail: View {
    let url: URL?
    var size: CGFloat = 64
    var placeholderSystemImage = "photo"
    var cornerRadius: CGFloat = 12
    @State private var loadedImage: UIImage?
    @State private var didFinishLoading = false

    var body: some View {
        Group {
            if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
        .task(id: "\(url?.absoluteString ?? "")|\(size)") {
            loadedImage = nil
            didFinishLoading = url == nil
            guard let url else { return }
            let image = await ImagePipeline.shared.image(for: url, targetSize: size)
            guard !Task.isCancelled else { return }
            loadedImage = image
            didFinishLoading = true
        }
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: placeholderSystemImage)
                .font(.title3)
                .foregroundStyle(.tertiary)
        }
        .opacity(didFinishLoading ? 1 : 0.72)
        .animation(
            didFinishLoading ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
            value: didFinishLoading
        )
    }
}

struct CafeMenuThumbnail: View {
    let url: URL?
    var size: CGFloat = 64
    let isSoldOut: Bool

    var body: some View {
        RemoteThumbnail(url: url, size: size)
            .saturation(isSoldOut ? 0.15 : 1)
            .opacity(isSoldOut ? 0.45 : 1)
            .overlay {
                if isSoldOut {
                    Text("품절")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.red, in: Capsule())
                }
            }
            .accessibilityHidden(true)
    }
}

struct LoadingContentView: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ForEach(0..<4, id: \.self) { index in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.quaternary)
                            .frame(width: index.isMultiple(of: 2) ? 150 : 190, height: 15)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.quaternary)
                            .frame(width: 112, height: 11)
                    }
                    Spacer()
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

struct CafeMenuListPlaceholder: View {
    var body: some View {
        LoadingContentView(title: "카페 메뉴를 준비하는 중…")
    }
}

struct CardLoadingPlaceholder: View {
    let title: String
    var rows = 3
    var showsBackground = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            ForEach(0..<rows, id: \.self) { index in
                if index > 0 { Divider() }
                HStack(spacing: 10) {
                    Circle().fill(.quaternary).frame(width: 22, height: 22)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .frame(width: index.isMultiple(of: 2) ? 156 : 126, height: 14)
                    Spacer()
                }
                .frame(minHeight: 32)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            showsBackground ? Color(.secondarySystemGroupedBackground) : Color.clear,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

struct FailureContentView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("불러오지 못했습니다", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("다시 시도", action: retry)
        }
    }
}

struct PriceText: View {
    let amount: Int

    var body: some View {
        Text(AppFormat.won(amount))
            .font(.body.monospacedDigit().weight(.semibold))
            .accessibilityLabel("가격 \(AppFormat.won(amount))")
    }
}

struct MenuDescriptionText: View {
    let text: String
    var mode: MenuDescriptionSummarizationMode = .menuComponents
    var onResolved: ((String) -> Void)? = nil
    @State private var generatedSummary: String? = nil

    private var fallback: String { MenuDescriptionFormatter.fallback(text) }

    var body: some View {
        HStack(spacing: 4) {
            Text(generatedSummary ?? fallback)
                .lineLimit(1)
                .truncationMode(.tail)

            if let generatedSummary, generatedSummary != fallback {
                Image(systemName: "apple.intelligence")
                    .font(.caption2)
                    .accessibilityLabel("기기에서 요약됨")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .task(id: "\(mode.rawValue)|\(text)") {
            generatedSummary = nil
            let summary = await MenuDescriptionSummarizer.shared.summary(for: text, mode: mode)
            guard !Task.isCancelled else { return }
            generatedSummary = summary
            onResolved?(summary)
        }
    }
}

struct SelectionChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                if isSelected {
                    Button(title, action: action).buttonStyle(.glassProminent)
                } else {
                    Button(title, action: action).buttonStyle(.glass)
                }
            } else {
                if isSelected {
                    Button(title, action: action).buttonStyle(.borderedProminent)
                } else {
                    Button(title, action: action).buttonStyle(.bordered)
                }
            }
        }
        .controlSize(.regular)
        .frame(minHeight: 44)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct CafeShopPickerMenu: View {
    let shops: [Shop]
    let selectedShopID: Int
    let selectShop: (Int) -> Void

    private var selectedShopName: String {
        shops.first(where: { $0.id == selectedShopID })?.name ?? "매장 선택"
    }

    var body: some View {
        Menu {
            ForEach(shops) { shop in
                Button {
                    selectShop(shop.id)
                } label: {
                    if shop.id == selectedShopID {
                        Label(shop.name, systemImage: "checkmark")
                    } else {
                        Text(shop.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(selectedShopName)
                    .font(.headline)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .disabled(shops.isEmpty)
        .accessibilityLabel("카페 매장")
        .accessibilityValue(selectedShopName)
        .accessibilityIdentifier("cafe.shop-picker")
        .accessibilityShowsLargeContentViewer {
            Label(selectedShopName, systemImage: "cup.and.saucer")
        }
    }
}

enum CafeShopSwitcherPolicy {
    static func adjacentShopID(
        in shops: [Shop],
        selectedShopID: Int,
        offset: Int
    ) -> Int? {
        guard shops.count > 1,
              let currentIndex = shops.firstIndex(where: { $0.id == selectedShopID })
        else { return nil }
        let nextIndex = (currentIndex + offset % shops.count + shops.count) % shops.count
        return shops[nextIndex].id
    }
}

struct CafeShopThumbSwitcher: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let shops: [Shop]
    let selectedShopID: Int
    let selectShop: (Int) -> Void

    @State private var isShopListPresented = false

    private var selectedShopName: String {
        shops.first(where: { $0.id == selectedShopID })?.name ?? "매장 선택"
    }

    var body: some View {
        HStack(spacing: 0) {
            switchButton(
                title: "이전 매장",
                systemImage: "chevron.left",
                offset: -1
            )

            Button {
                isShopListPresented = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.caption)
                        .foregroundStyle(AppPalette.brand)
                    Text(selectedShopName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.up")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("카페 매장 선택")
            .accessibilityValue(selectedShopName)
            .accessibilityHint("전체 매장 목록을 엽니다")
            .accessibilityIdentifier("cafe.shop-thumb-switcher.current")

            switchButton(
                title: "다음 매장",
                systemImage: "chevron.right",
                offset: 1
            )
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: 380, minHeight: 44, maxHeight: 44)
        .appGlassSurface(cornerRadius: 22, isInteractive: true)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height),
                          abs(value.translation.width) >= 44
                    else { return }
                    selectAdjacentShop(offset: value.translation.width < 0 ? 1 : -1)
                }
        )
        .sheet(isPresented: $isShopListPresented) {
            CafeShopSelectionSheet(
                shops: shops,
                selectedShopID: selectedShopID,
                selectShop: selectShop
            )
            .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sensoryFeedback(.selection, trigger: selectedShopID)
    }

    private func switchButton(title: String, systemImage: String, offset: Int) -> some View {
        Button {
            selectAdjacentShop(offset: offset)
        } label: {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(shops.count < 2)
        .accessibilityLabel(title)
        .accessibilityIdentifier("cafe.shop-thumb-switcher.\(offset < 0 ? "previous" : "next")")
    }

    private func selectAdjacentShop(offset: Int) {
        guard let id = CafeShopSwitcherPolicy.adjacentShopID(
            in: shops,
            selectedShopID: selectedShopID,
            offset: offset
        ) else { return }
        selectShop(id)
    }
}

private struct CafeShopSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let shops: [Shop]
    let selectedShopID: Int
    let selectShop: (Int) -> Void

    var body: some View {
        NavigationStack {
            List(shops) { shop in
                Button {
                    selectShop(shop.id)
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "cup.and.saucer.fill")
                            .frame(width: 32, height: 32)
                            .foregroundStyle(shop.id == selectedShopID ? AppPalette.brand : .secondary)
                            .background(.quaternary, in: Circle())

                        Text(shop.name)
                            .font(.body.weight(shop.id == selectedShopID ? .semibold : .regular))
                            .foregroundStyle(.primary)

                        Spacer(minLength: 12)

                        if shop.id == selectedShopID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppPalette.brand)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(shop.name)
                .accessibilityValue(shop.id == selectedShopID ? "선택됨" : "")
            }
            .navigationTitle("카페 매장")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }
}

#if DEBUG
struct CafeShopThumbSwitcherFixtureView: View {
    @State private var selectedTab = 2
    @State private var selectedShopID = 5

    private let shops = [
        Shop(id: 5, name: "카카오 판교 아지트 카페", kind: .cafe, isOpen: true),
        Shop(id: 6, name: "카카오 제주 스페이스 카페", kind: .cafe, isOpen: true),
        Shop(id: 8, name: "카카오 AI 캠퍼스 카페", kind: .cafe, isOpen: true),
    ]

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("홈", systemImage: "house", value: 0) { Color.clear }
            Tab("식단", systemImage: "fork.knife", value: 1) { Color.clear }
            Tab("카페", systemImage: "cup.and.saucer", value: 2) {
                NavigationStack {
                    List {
                        Section("최근·인기 메뉴") {
                            fixtureRow("아이스 아메리카노", detail: "BEST · 3,500원")
                            fixtureRow("카페 라떼", detail: "즐겨찾기 · 4,500원")
                        }
                        Section("전체 메뉴") {
                            fixtureRow("바닐라 라떼", detail: "4,800원")
                            fixtureRow("콜드브루", detail: "4,300원")
                            fixtureRow("말차 크림 라떼", detail: "NEW · 5,200원")
                        }
                    }
                    .navigationTitle("카페")
                    .navigationBarTitleDisplayMode(.inline)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        CafeShopThumbSwitcher(
                            shops: shops,
                            selectedShopID: selectedShopID,
                            selectShop: { selectedShopID = $0 }
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    }
                }
            }
            Tab("장바구니", systemImage: "bag", value: 3) { Color.clear }
            Tab("내역", systemImage: "receipt", value: 4) { Color.clear }
        }
        .tint(AppPalette.brand)
    }

    private func fixtureRow(_ title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppPalette.brand.opacity(0.16))
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "cup.and.saucer.fill")
                        .foregroundStyle(AppPalette.brand)
                        .accessibilityHidden(true)
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct CafeShopPickerFixtureView: View {
    @State private var selectedShopID = 5

    private let shops = [
        Shop(id: 5, name: "엘리가 카페 본점", kind: .cafe, isOpen: true),
        Shop(id: 6, name: "엘리가 카페 서초점", kind: .cafe, isOpen: true),
    ]

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "장바구니가 비어 있습니다",
                systemImage: "bag",
                description: Text("카페 메뉴에서 음료를 담아 보세요.")
                    .foregroundStyle(.primary)
            )
            .navigationTitle("장바구니")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    CafeShopPickerMenu(
                        shops: shops,
                        selectedShopID: selectedShopID,
                        selectShop: { selectedShopID = $0 }
                    )
                }
            }
        }
    }
}
#endif

struct MenuLabelBadge: View {
    enum Size {
        case compact
        case regular
    }

    let text: String
    var size: Size = .compact

    var body: some View {
        Text(text)
            .font(size == .compact ? .caption2.weight(.bold) : .caption.weight(.bold))
            .foregroundStyle(.primary)
            .padding(.horizontal, size == .compact ? 5 : 7)
            .padding(.vertical, 2)
            .background(foregroundColor.opacity(0.16), in: Capsule())
            .lineLimit(1)
            .accessibilityLabel("\(text) 배지")
    }

    private var foregroundColor: Color {
        switch text.uppercased() {
        case "BEST": .orange
        case "NEW": .blue
        default: .purple
        }
    }
}

struct CafeMenuRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let item: CafeMenuItem
    let isFavorite: Bool
    let quantity: Int
    let orderState: CafeOrderState
    let toggleFavorite: () -> Void
    let decrease: () -> Void
    let increase: () -> Void
    let openDetail: () -> Void
    let quickOrder: () -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    detailButton
                    if !item.isSoldOut {
                        HStack {
                            Spacer()
                            quantityControl
                        }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    detailButton
                    if !item.isSoldOut { quantityControl }
                }
            }
        }
        .frame(minHeight: 64)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: toggleFavorite) {
                Label(isFavorite ? "즐겨찾기 해제" : "즐겨찾기", systemImage: isFavorite ? "star.slash" : "star")
            }
            .tint(isFavorite ? .gray : .yellow)
        }
        .contextMenu {
            Button("상세 보기", systemImage: "info.circle", action: openDetail)
            Button(
                isFavorite ? "즐겨찾기 해제" : "즐겨찾기에 추가",
                systemImage: isFavorite ? "star.slash" : "star",
                action: toggleFavorite
            )

            Divider()
            orderContextActions
        }
        .accessibilityAction(
            named: Text(isFavorite ? "즐겨찾기 해제" : "즐겨찾기"),
            toggleFavorite
        )
    }

    private var detailButton: some View {
        Button(action: openDetail) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        menuThumbnail
                        menuCopy
                    }
                } else {
                    HStack(spacing: 10) {
                        menuThumbnail
                        menuCopy
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .layoutPriority(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(menuAccessibilityLabel)
        .accessibilityHint("메뉴 상세 정보를 엽니다")
    }

    private var menuThumbnail: some View {
        CafeMenuThumbnail(
            url: item.thumbnailURL,
            size: 64,
            isSoldOut: item.isSoldOut
        )
    }

    private var menuCopy: some View {
        VStack(alignment: .leading, spacing: 3) {
            menuTitle

            if !dynamicTypeSize.isAccessibilitySize,
               let description = item.description,
               !description.isEmpty {
                MenuDescriptionText(text: description)
            }

            Text(AppFormat.won(item.price))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var menuTitle: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    if let label = item.label, !label.isEmpty {
                        MenuLabelBadge(text: label)
                    }
                    if isFavorite { favoriteIcon }
                }
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(2)
            }
        } else {
            HStack(spacing: 5) {
                if let label = item.label, !label.isEmpty {
                    MenuLabelBadge(text: label)
                }
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if isFavorite { favoriteIcon }
            }
        }
    }

    private var favoriteIcon: some View {
        Image(systemName: "star.fill")
            .font(.caption2)
            .foregroundStyle(.yellow)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var orderContextActions: some View {
        if item.isSoldOut || item.goodsID == nil {
            Button("품절된 메뉴", systemImage: "xmark.circle") {}
                .disabled(true)
        } else if !orderState.isOrderable {
            Button("현재 주문 불가", systemImage: "clock") {}
                .disabled(true)
        } else {
            Button(
                quantity > 0 ? "하나 더 담기" : "장바구니에 담기",
                systemImage: "bag.badge.plus",
                action: increase
            )

            if quantity > 0 {
                Button("하나 빼기", systemImage: "minus.circle", action: decrease)
            }

            Button("바로 주문", systemImage: "bolt.fill", action: quickOrder)
        }
    }

    private var menuAccessibilityLabel: String {
        let summary = "\(item.name), \(AppFormat.won(item.price))"
        return item.isSoldOut ? "\(summary), 품절" : summary
    }

    @ViewBuilder
    private var quantityControl: some View {
        if quantity == 0 {
            Button("장바구니에 담기", systemImage: "plus", action: increase)
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .buttonStyle(.bordered)
                .frame(minWidth: 44, minHeight: 44)
                .disabled(!orderState.isOrderable || item.goodsID == nil)
                .accessibilityLabel("\(item.name) 장바구니에 담기")
        } else {
            HStack(spacing: 0) {
                Button("수량 감소", systemImage: "minus", action: decrease)
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())

                Text("\(quantity)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .contentTransition(.numericText())
                    .frame(minWidth: 22)
                    .accessibilityLabel("수량 \(quantity)개")

                Button("수량 증가", systemImage: "plus", action: increase)
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .disabled(!orderState.isOrderable || item.goodsID == nil)
            }
            .buttonStyle(.plain)
            .background(.quaternary, in: Capsule())
            .accessibilityElement(children: .contain)
        }
    }
}
