import SwiftUI
import UIKit

struct RemoteThumbnail: View {
    let url: URL?
    var size: CGFloat = 64
    var placeholderSystemImage = "photo"
    var cornerRadius: CGFloat = 12
    var contentMode: ContentMode = .fill
    @State private var loadedImage: UIImage?
    @State private var didFinishLoading = false

    var body: some View {
        Group {
            if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
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
        guard let match = floorMatch(for: shopName) else {
            var title = shopName.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.hasPrefix("카카오 ") {
                title.removeFirst("카카오 ".count)
            }
            if title.hasSuffix(" 카페") {
                title.removeLast(" 카페".count)
            }
            return title.isEmpty ? shopName : title
        }
        guard !match.wing.isEmpty else { return "\(match.floor)F" }
        return "\(match.floor)F \(match.wing)"
    }

    /// Orders shops by ascending floor (then by wing letter, so e.g. `"5F"`
    /// sorts before `"5F b"`) regardless of the raw API order. Shops without
    /// a parseable floor number sort after every floor-numbered shop,
    /// alphabetically by name among themselves.
    static func sortedByFloor(_ shops: [Shop]) -> [Shop] {
        shops.sorted { lhs, rhs in
            switch (floorMatch(for: lhs.name), floorMatch(for: rhs.name)) {
            case let (l?, r?):
                return l.floor != r.floor ? l.floor < r.floor : l.wing < r.wing
            case (nil, .some):
                return false
            case (.some, nil):
                return true
            case (nil, nil):
                return lhs.name < rhs.name
            }
        }
    }

    /// Real shop names can carry a combining/precomposed diacritic (e.g.
    /// "kafé") that isn't relevant to the floor pattern — fold it away
    /// before matching.
    private static func floorMatch(for shopName: String) -> (floor: Int, wing: String)? {
        let folded = shopName.folding(options: .diacriticInsensitive, locale: nil) as NSString
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)\s*[Ff]\s*([a-zA-Z])?"#),
              let match = regex.firstMatch(in: folded as String, range: NSRange(location: 0, length: folded.length)),
              let floor = Int(folded.substring(with: match.range(at: 1)))
        else { return nil }
        let wingRange = match.range(at: 2)
        let wing = wingRange.location != NSNotFound ? folded.substring(with: wingRange).lowercased() : ""
        return (floor, wing)
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
    let shops: [Shop]
    let selectedShopID: Int
    let selectShop: (Int) -> Void
    /// Shop ID → item count, shown as a small badge on each chip so shops
    /// with something already in the cart are easy to spot without having
    /// to switch to each one. Empty by default (no badges).
    var itemCounts: [Int: Int] = [:]

    private let chipHeight: CGFloat = 40

    /// Ascending-floor order, regardless of the raw API order.
    private var sortedShops: [Shop] { CafeShopSwitcherPolicy.sortedByFloor(shops) }

    var body: some View {
        AppGlassGroup(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(sortedShops) { shop in
                    chip(for: shop)
                }
            }
        }
        // `.contain` (not the default) makes this its own AX element
        // carrying this identifier, while still exposing each shop button as
        // its own separate element — a plain container here would otherwise
        // leak this identifier onto every child button, clobbering their
        // individual "cafe.shop-mode.<id>" identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cafe.shop-mode-switcher")
        .sensoryFeedback(.selection, trigger: selectedShopID)
    }

    private func chip(for shop: Shop) -> some View {
        let isSelected = shop.id == selectedShopID
        let itemCount = itemCounts[shop.id] ?? 0

        return Button {
            guard shop.id != selectedShopID else { return }
            withAnimation(.snappy(duration: 0.28)) {
                selectShop(shop.id)
            }
        } label: {
            Text(CafeShopSwitcherPolicy.modeTitle(for: shop.name))
                .font(.subheadline.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
                .padding(.horizontal, 14)
                .frame(height: chipHeight)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modifier(ShopChipGlassBackground(isSelected: isSelected))
        .overlay(alignment: .topTrailing) {
            if itemCount > 0 {
                itemCountBadge(itemCount)
            }
        }
        .accessibilityLabel(shop.name)
        .accessibilityValue([isSelected ? "선택됨" : "", itemCount > 0 ? "장바구니 \(itemCount)개" : ""]
            .filter { !$0.isEmpty }
            .joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "현재 매장" : "이 매장으로 변경")
        .accessibilityIdentifier("cafe.shop-mode.\(shop.id)")
        .accessibilityShowsLargeContentViewer {
            Label(shop.name, systemImage: "cup.and.saucer.fill")
        }
    }

    private func itemCountBadge(_ count: Int) -> some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, count > 9 ? 4 : 0)
            .frame(minWidth: 16, minHeight: 16)
            .background(Color.red, in: Capsule())
            .offset(x: 6, y: -6)
            .accessibilityHidden(true)
    }
}

/// Each shop chip is its own independent glass shape (not one shared capsule
/// with a sliding highlight) — the selected chip is tinted with the brand
/// color so it reads like a filled pill next to its plain-glass neighbors.
/// Falls back to a solid brand-color capsule (not just a faint tint) when
/// reduced transparency or pre-iOS 26 glass isn't available, so the selected
/// chip still has enough contrast for its white label.
private struct ShopChipGlassBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let isSelected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *), !reduceTransparency {
            content.glassEffect(
                isSelected ? .regular.tint(AppPalette.brand).interactive() : .regular.interactive(),
                in: .capsule
            )
        } else if isSelected {
            content.background(AppPalette.brand, in: Capsule())
        } else if reduceTransparency {
            content
                .background(Color(.secondarySystemBackground), in: Capsule())
                .overlay { Capsule().stroke(.primary.opacity(0.14), lineWidth: 1) }
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay { Capsule().stroke(.primary.opacity(0.08), lineWidth: 0.5) }
        }
    }
}

extension View {
    /// Swiping anywhere on this view — including over the menu/cart `List`
    /// underneath — steps to the adjacent shop (in ascending-floor order).
    /// Replaces the switcher's own local swipe-to-step gesture so the whole
    /// screen is swipeable, not just the small chip strip.
    ///
    /// A plain SwiftUI `DragGesture` (even `highPriorityGesture`, even
    /// backed by a sibling `UIViewRepresentable`) doesn't reliably see
    /// horizontal drags that start over a `List`: its backing
    /// `UICollectionView` has its own pan gesture recognizer that wins the
    /// touch before a sibling view's recognizer is even offered it — touch
    /// delivery only reaches a hit-tested view's own gesture recognizers and
    /// those of its *ancestors*, not siblings. `UIGestureRecognizerRepresentable`
    /// (iOS 18+) attaches the recognizer directly to this view's own backing
    /// UIKit layer instead of a separate sibling, so it sits in the same
    /// touch-delivery chain as the List and, with simultaneous recognition
    /// opted in, reliably fires alongside its scrolling.
    func shopSwipeNavigation(
        shops: [Shop],
        selectedShopID: Int,
        isEnabled: Bool = true,
        selectShop: @escaping (Int) -> Void
    ) -> some View {
        // Sparse content — an empty-state `ContentUnavailableView`, a
        // centered loading spinner, a failure card — only has its actual
        // glyphs (icon, text) hit-testable by default; the surrounding
        // whitespace that makes up most of the screen passes touches
        // through untouched, so a swipe starting there never reaches this
        // gesture at all. `List`'s backing `UICollectionView` fills its
        // whole frame and doesn't have this gap, which is why the same
        // swipe already worked reliably once a shop had a populated menu.
        // `.contentShape` makes the full frame hit-testable regardless of
        // what's actually drawn in it, so every content state behaves the
        // same as the List case.
        contentShape(Rectangle())
            .gesture(
                ShopSwipeGesture { isLeftward in
                    guard isEnabled else { return }
                    guard let nextShopID = CafeShopSwitcherPolicy.adjacentShopID(
                        in: CafeShopSwitcherPolicy.sortedByFloor(shops),
                        selectedShopID: selectedShopID,
                        offset: isLeftward ? 1 : -1
                    ) else { return }
                    withAnimation(.snappy(duration: 0.28)) {
                        selectShop(nextShopID)
                    }
                }
            )
    }

    /// Disables the system's screen-edge back-swipe while `isDisabled` is
    /// true, restoring it otherwise.
    ///
    /// `UINavigationController.interactivePopGestureRecognizer` is a
    /// screen-edge pan bound to the *whole* nav stack. When a touch begins
    /// near the left edge it wins that touch outright — before our own
    /// `shopSwipeNavigation` pan gesture is even offered it — even when
    /// there's nothing to pop back to at a tab's root. That silently
    /// swallows every rightward swipe (finger moving left→right) that
    /// happens to start close to the edge, while leftward swipes (starting
    /// from the right side) never come near it — the exact one-sided
    /// "swipe left works, swipe right doesn't" symptom this fixes. Only
    /// disable while there's truly nothing to pop (`isDisabled` should be
    /// tied to the tab's path being empty) so back-swipe still works
    /// normally on pushed detail screens.
    func disablesInteractivePopGesture(while isDisabled: Bool) -> some View {
        background(InteractivePopGestureDisabler(isDisabled: isDisabled))
    }
}

private struct InteractivePopGestureDisabler: UIViewControllerRepresentable {
    let isDisabled: Bool

    func makeUIViewController(context: Context) -> InteractivePopGestureAccessController {
        InteractivePopGestureAccessController()
    }

    func updateUIViewController(_ uiViewController: InteractivePopGestureAccessController, context: Context) {
        uiViewController.isDisabled = isDisabled
    }
}

/// Zero-size, non-interactive host controller used only to reach the
/// enclosing `UINavigationController` and toggle its interactive pop
/// gesture. See `disablesInteractivePopGesture(while:)`.
private final class InteractivePopGestureAccessController: UIViewController {
    var isDisabled = false {
        didSet { applyState() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyState()
    }

    override func willMove(toParent parent: UIViewController?) {
        super.willMove(toParent: parent)
        guard parent == nil else { return }
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }

    private func applyState() {
        navigationController?.interactivePopGestureRecognizer?.isEnabled = !isDisabled
    }
}

/// See `shopSwipeNavigation(shops:selectedShopID:selectShop:)`.
private struct ShopSwipeGesture: UIGestureRecognizerRepresentable {
    let onSwipe: (_ isLeftward: Bool) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        UIPanGestureRecognizer()
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UIPanGestureRecognizer,
        context: Context
    ) {
        guard recognizer.state == .ended else { return }
        let translation = recognizer.translation(in: recognizer.view)
        guard abs(translation.x) > abs(translation.y), abs(translation.x) >= 60 else { return }
        onSwipe(translation.x < 0)
    }

    func gestureRecognizer(
        _ recognizer: UIPanGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer,
        context: Context
    ) -> Bool {
        true
    }
}

/// Top-of-screen shop switcher + an optional trailing accessory button
/// (search on CafeView, clear-cart on CartView) — placed via
/// `.safeAreaInset(edge: .top)` right under the navigation bar.
struct CafeShopHeaderBar: View {
    /// A small circular accessory button that sits to the right of the shop
    /// switcher.
    struct TrailingAccessory {
        let systemImage: String
        let accessibilityLabel: String
        let accessibilityIdentifier: String
        var isDestructive = false
        let action: () -> Void
    }

    let shops: [Shop]
    let selectedShopID: Int
    let selectShop: (Int) -> Void
    /// `nil` hides the trailing button entirely.
    var trailingAccessory: TrailingAccessory? = nil
    /// Shop ID → item count, forwarded to CafeShopModeSwitcher's badges.
    var itemCounts: [Int: Int] = [:]

    private let controlHeight: CGFloat = 40

    var body: some View {
        HStack(spacing: 10) {
            if shops.count > 1 {
                CafeShopModeSwitcher(
                    shops: shops,
                    selectedShopID: selectedShopID,
                    selectShop: selectShop,
                    itemCounts: itemCounts
                )
            }
            Spacer(minLength: 0)
            if let trailingAccessory {
                accessoryButton(trailingAccessory)
            }
        }
        .frame(height: controlHeight)
    }

    private func accessoryButton(_ accessory: TrailingAccessory) -> some View {
        Button(action: accessory.action) {
            Image(systemName: accessory.systemImage)
                .font(.body.weight(.semibold))
                .frame(width: controlHeight, height: controlHeight)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .appGlassSurface(cornerRadius: controlHeight / 2, isInteractive: true)
        .foregroundStyle(accessory.isDestructive ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
        .accessibilityLabel(accessory.accessibilityLabel)
        .accessibilityIdentifier(accessory.accessibilityIdentifier)
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
        // A separate, lower floor range (1F/2F) so this pair doesn't
        // disturb the 3F/4F/5F-b adjacency the swipe/tap test above relies
        // on. id10 (1F) is a populated neighbor on both sides of id9 (2F,
        // empty menu) — id9 needs a valid neighbor in BOTH directions to
        // exercise left AND right swipe from an empty state, unlike id6
        // (3F), which is first in floor order and has no leading neighbor.
        Shop(id: 10, name: "kafé 1F", kind: .cafe, isOpen: true),
        Shop(id: 9, name: "kafé 2F", kind: .cafe, isOpen: true),
    ]

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("홈", systemImage: "house", value: 0) { Color.clear }
            Tab("식단", systemImage: "fork.knife", value: 1) { Color.clear }
            Tab("카페", systemImage: "cup.and.saucer", value: 2) {
                NavigationStack {
                    ZStack {
                        Group {
                            if selectedShopID == 6 || selectedShopID == 9 {
                                ContentUnavailableView(
                                    "등록된 메뉴가 없습니다",
                                    systemImage: "cup.and.saucer",
                                    description: Text("잠시 후 다시 확인해 주세요.")
                                )
                            } else {
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
                            }
                        }
                        .id(selectedShopID)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .navigationTitle("카페")
                    .navigationBarTitleDisplayMode(.inline)
                    .modifier(
                        CafeSearchFixtureModifier(
                            text: $searchText,
                            isPresented: $isSearchPresented
                        )
                    )
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if !isSearchPresented {
                            CafeShopHeaderBar(
                                shops: shops,
                                selectedShopID: selectedShopID,
                                selectShop: { selectedShopID = $0 },
                                trailingAccessory: CafeShopHeaderBar.TrailingAccessory(
                                    systemImage: "magnifyingglass",
                                    accessibilityLabel: "메뉴 검색",
                                    accessibilityIdentifier: "cafe.search.accessory",
                                    action: { isSearchPresented = true }
                                )
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 6)
                        }
                    }
                    .shopSwipeNavigation(
                        shops: shops,
                        selectedShopID: selectedShopID,
                        selectShop: { selectedShopID = $0 }
                    )
                    .disablesInteractivePopGesture(while: true)
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

/// Exercises the cart screen's own shop switcher (same top-header chips as
/// CafeView, minus the search button) without needing a real cart/API
/// session. Wrapped in a TabView, like CafeShopModeSwitcherFixtureView, so
/// the switcher sits under a real nav bar above a real GNB — matching
/// production layout.
struct CartShopSwitcherFixtureView: View {
    @State private var selectedTab = 3
    @State private var selectedShopID = 5

    // Deliberately stored out of floor order (5F b before 3F) so the
    // fixture also exercises CafeShopSwitcherPolicy.sortedByFloor.
    private let shops = [
        Shop(id: 5, name: "kafé 5F b", kind: .cafe, isOpen: true),
        Shop(id: 6, name: "kafé 3F", kind: .cafe, isOpen: true),
    ]

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("홈", systemImage: "house", value: 0) { Color.clear }
            Tab("식단", systemImage: "fork.knife", value: 1) { Color.clear }
            Tab("카페", systemImage: "cup.and.saucer", value: 2) { Color.clear }
            Tab("장바구니", systemImage: "bag", value: 3) {
                NavigationStack {
                    ContentUnavailableView(
                        "장바구니가 비어 있습니다",
                        systemImage: "bag",
                        description: Text("카페 메뉴에서 음료를 담아 보세요.")
                            .foregroundStyle(.primary)
                    )
                    .navigationTitle("장바구니")
                    .navigationBarTitleDisplayMode(.inline)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        CafeShopHeaderBar(
                            shops: shops,
                            selectedShopID: selectedShopID,
                            selectShop: { selectedShopID = $0 }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 6)
                    }
                }
            }
            Tab("내역", systemImage: "receipt", value: 4) { Color.clear }
        }
        .tabViewStyle(.sidebarAdaptable)
        .appTabBarBehavior()
        .tint(AppPalette.brand)
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
        .sensoryFeedback(.selection, trigger: isFavorite)
        .sensoryFeedback(.selection, trigger: quantity)
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
