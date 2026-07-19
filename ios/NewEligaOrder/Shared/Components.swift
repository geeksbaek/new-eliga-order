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

enum CafeShopSwitcherPolicy {
    static func adjacentShopID(
        in shops: [Shop],
        selectedShopID: Int,
        offset: Int
    ) -> Int? {
        guard shops.count > 1,
              let currentIndex = shops.firstIndex(where: { $0.id == selectedShopID })
        else { return nil }
        let nextIndex = currentIndex + offset
        guard shops.indices.contains(nextIndex) else { return nil }
        return shops[nextIndex].id
    }

    /// Normalizes a shop's raw name down to just its floor label for the
    /// compact mode-switcher chip — e.g. `"춘식도락 with in the box(4F)"` →
    /// `"4F"`, `"kafé 5F"` → `"5F"`, `"kafé 5F b"` → `"5F b"` (the 5th floor
    /// has two cafes, in the main building and the "b" wing). Falls back to
    /// the legacy "strip 카카오 prefix / 카페 suffix" trimming for names
    /// without a floor number.
    static func modeTitle(for shopName: String) -> String {
        // Real shop names can carry a combining/precomposed diacritic (e.g.
        // "kafé") that isn't relevant to the floor pattern — fold it away
        // before matching.
        let folded = shopName.folding(options: .diacriticInsensitive, locale: nil) as NSString
        if let regex = try? NSRegularExpression(pattern: #"(\d+)\s*[Ff]\s*([a-zA-Z])?"#),
           let match = regex.firstMatch(in: folded as String, range: NSRange(location: 0, length: folded.length)) {
            let floor = folded.substring(with: match.range(at: 1))
            let wingRange = match.range(at: 2)
            guard wingRange.location != NSNotFound else { return "\(floor)F" }
            return "\(floor)F \(folded.substring(with: wingRange).lowercased())"
        }

        var title = shopName.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.hasPrefix("카카오 ") {
            title.removeFirst("카카오 ".count)
        }
        if title.hasSuffix(" 카페") {
            title.removeLast(" 카페".count)
        }
        return title.isEmpty ? shopName : title
    }
}

/// Liquid Glass segmented control for switching cafe shops. Shows every shop
/// at once (no horizontal scroll): with the realistic 2-4 shop count, "swipe
/// to reveal more" pays a discovery tax for information that just fits on
/// screen, and reads as borrowing the Camera app's mode-strip look rather
/// than owning a shape suited to this content. Showing everything up front
/// and letting the morphing selection pill carry the delight instead is the
/// more deliberate, modern read — the pill-morph and swipe-to-step gesture
/// are the parts of the old camera-strip design worth keeping.
struct CafeShopModeSwitcher: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    let shops: [Shop]
    let selectedShopID: Int
    let selectShop: (Int) -> Void

    @Namespace private var selectionNamespace
    private let trackHeight: CGFloat = 44

    var body: some View {
        modeStrip
            .frame(height: trackHeight)
            .frame(maxWidth: .infinity)
            .sensoryFeedback(.selection, trigger: selectedShopID)
    }

    @ViewBuilder
    private var modeStrip: some View {
        if #available(iOS 26, *), !reduceTransparency {
            GlassEffectContainer(spacing: 12) {
                modeRow
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
        } else {
            modeRow
                .background(
                    reduceTransparency ? AnyShapeStyle(Color(.secondarySystemBackground)) : AnyShapeStyle(.regularMaterial),
                    in: Capsule()
                )
                .overlay {
                    Capsule().stroke(.primary.opacity(0.1), lineWidth: 0.5)
                }
        }
    }

    private var modeRow: some View {
        HStack(spacing: 2) {
            ForEach(shops) { shop in
                modeButton(for: shop)
            }
        }
        .padding(3)
        .simultaneousGesture(
            // Keeps the camera strip's swipe-to-step feel even without a
            // scroll view backing it: a drag anywhere on the track steps
            // selection to the neighboring shop.
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let translation = value.translation
                    guard abs(translation.width) > abs(translation.height),
                          abs(translation.width) >= 44
                    else { return }
                    selectAdjacentShop(offset: translation.width < 0 ? 1 : -1)
                }
        )
        // `.contain` (not the default) makes this HStack its own AX element
        // carrying this identifier, while still exposing each shop button as
        // its own separate element — a plain container here would otherwise
        // leak this identifier onto every child button, clobbering their
        // individual "cafe.shop-mode.<id>" identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cafe.shop-mode-switcher")
    }

    private func modeButton(for shop: Shop) -> some View {
        let isSelected = shop.id == selectedShopID

        return Button {
            guard shop.id != selectedShopID else { return }
            withAnimation(.snappy(duration: 0.28)) {
                selectShop(shop.id)
            }
        } label: {
            Text(CafeShopSwitcherPolicy.modeTitle(for: shop.name))
                .font(.subheadline.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: trackHeight - 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                selectionSurface
            }
        }
        .accessibilityLabel(shop.name)
        .accessibilityValue(isSelected ? "선택됨" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "현재 매장" : "이 매장으로 변경")
        .accessibilityIdentifier("cafe.shop-mode.\(shop.id)")
        .accessibilityShowsLargeContentViewer {
            Label(shop.name, systemImage: "cup.and.saucer.fill")
        }
    }

    @ViewBuilder
    private var selectionSurface: some View {
        if #available(iOS 26, *), !reduceTransparency {
            // Morphing selection pill — slides/resizes between chips of
            // different widths as the selected shop changes.
            Color.clear
                .glassEffect(
                    .regular
                        .tint(selectionTint)
                        .interactive(),
                    in: .capsule
                )
                .glassEffectID("cafe-selected-shop", in: selectionNamespace)
        } else {
            Capsule()
                .fill(Color.primary.opacity(reduceTransparency ? 0.12 : 0.08))
                .overlay {
                    Capsule().stroke(.primary.opacity(0.1), lineWidth: 0.5)
                }
        }
    }

    private var selectionTint: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.22)
            : Color.white.opacity(0.55)
    }

    private func selectAdjacentShop(offset: Int) {
        guard let shopID = CafeShopSwitcherPolicy.adjacentShopID(
            in: shops,
            selectedShopID: selectedShopID,
            offset: offset
        ) else { return }
        withAnimation(.snappy(duration: 0.28)) {
            selectShop(shopID)
        }
    }
}

/// CafeView's own bottom row: shop switcher (when there's more than one shop
/// to pick between) plus a small circular search-trigger button. Lives
/// entirely in CafeView's view tree via `.safeAreaInset` — no
/// `tabViewBottomAccessory`, no syncing with the GNB's own collapse
/// behavior. Each control keeps its own Liquid Glass surface, so they read
/// as two distinct floating shapes rather than one shared system bar.
struct CafeBottomControlsRow: View {
    let shops: [Shop]
    let selectedShopID: Int
    let selectShop: (Int) -> Void
    let searchAction: () -> Void

    private let controlHeight: CGFloat = 44

    var body: some View {
        AppGlassGroup(spacing: 12) {
            HStack(spacing: 12) {
                if shops.count > 1 {
                    CafeShopModeSwitcher(
                        shops: shops,
                        selectedShopID: selectedShopID,
                        selectShop: selectShop
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    Spacer(minLength: 0)
                }
                searchButton
            }
        }
        .frame(height: controlHeight)
    }

    private var searchButton: some View {
        Button(action: searchAction) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .frame(width: controlHeight, height: controlHeight)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .appGlassSurface(cornerRadius: controlHeight / 2, isInteractive: true)
        .accessibilityLabel("메뉴 검색")
        .accessibilityIdentifier("cafe.search.accessory")
    }
}

#if DEBUG
struct CafeShopModeSwitcherFixtureView: View {
    @State private var selectedTab = 2
    @State private var selectedShopID = 5
    @State private var searchText = ""
    @State private var isSearchPresented = false

    private let shops = [
        // Real backend shop names, exercised here so the fixture matches
        // what CafeShopSwitcherPolicy.modeTitle actually normalizes in
        // production ("kafé" arrives with a precomposed diacritic).
        Shop(id: 5, name: "춘식도락 with in the box(4F)", kind: .cafe, isOpen: true),
        Shop(id: 6, name: "kafé 3F", kind: .cafe, isOpen: true),
        Shop(id: 8, name: "kafé 5F b", kind: .cafe, isOpen: true),
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
                            fixtureRow("에스프레소", detail: "3,000원")
                            fixtureRow("카푸치노", detail: "4,200원")
                            fixtureRow("카라멜 마키아토", detail: "5,000원")
                            fixtureRow("자몽 에이드", detail: "4,800원")
                            fixtureRow("레몬 티", detail: "4,300원")
                        }
                    }
                    .navigationTitle("카페")
                    .navigationBarTitleDisplayMode(.inline)
                    .modifier(
                        CafeSearchFixtureModifier(
                            text: $searchText,
                            isPresented: $isSearchPresented
                        )
                    )
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if !isSearchPresented {
                            CafeBottomControlsRow(
                                shops: shops,
                                selectedShopID: selectedShopID,
                                selectShop: { selectedShopID = $0 },
                                searchAction: { isSearchPresented = true }
                            )
                            .padding(.horizontal, 12)
                            .padding(.top, 6)
                            .padding(.bottom, 8)
                        }
                    }
                }
            }
            Tab("장바구니", systemImage: "bag", value: 3) { Color.clear }
            Tab("내역", systemImage: "receipt", value: 4) { Color.clear }
        }
        .tabViewStyle(.sidebarAdaptable)
        .appTabBarBehavior()
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

/// Exercises the cart screen's own shop switcher (same segmented control as
/// CafeView, no search button) without needing a real cart/API session.
struct CartShopSwitcherFixtureView: View {
    @State private var selectedShopID = 5

    private let shops = [
        Shop(id: 5, name: "kafé 3F", kind: .cafe, isOpen: true),
        Shop(id: 6, name: "kafé 5F b", kind: .cafe, isOpen: true),
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
                    CafeShopModeSwitcher(
                        shops: shops,
                        selectedShopID: selectedShopID,
                        selectShop: { selectedShopID = $0 }
                    )
                }
            }
        }
    }
}

private struct CafeSearchFixtureModifier: ViewModifier {
    @Binding var text: String
    @Binding var isPresented: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isPresented {
            content.searchable(
                text: $text,
                isPresented: $isPresented,
                placement: .toolbar,
                prompt: "모든 매장의 메뉴 검색"
            )
        } else {
            content
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
