import SwiftUI

enum AppDesign {
    static let cardCornerRadius: CGFloat = 24
    static let controlCornerRadius: CGFloat = 18
    static let contentMaxWidth: CGFloat = 720
}

enum AppPalette {
    /// Dominant background color sampled from the production app icon (#B6574C).
    static let brand = Color.accentColor
}

struct AppAmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Color(.systemGroupedBackground)
        } else {
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.52, 0.48], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: meshColors,
                background: Color(.systemBackground),
                smoothsColors: true
            )
        }
    }

    private var meshColors: [Color] {
        let tintOpacity = colorScheme == .dark ? 0.24 : 0.15
        return [
            AppPalette.brand.opacity(tintOpacity), .clear, AppPalette.brand.opacity(tintOpacity * 0.55),
            .clear, AppPalette.brand.opacity(tintOpacity * 0.45), .clear,
            AppPalette.brand.opacity(tintOpacity * 0.35), .clear, AppPalette.brand.opacity(tintOpacity * 0.7),
        ]
    }
}

private struct AppGlassSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let cornerRadius: CGFloat
    let tint: Color?
    let isInteractive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *), !reduceTransparency {
            content
                .glassEffect(
                    .regular.tint(tint).interactive(isInteractive),
                    in: .rect(cornerRadius: cornerRadius)
                )
        } else if reduceTransparency {
            content
                .background(
                    tint?.opacity(0.16) ?? Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.primary.opacity(0.14), lineWidth: 1)
                }
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.primary.opacity(0.08), lineWidth: 0.5)
                }
        }
    }
}

extension View {
    func appGlassSurface(
        cornerRadius: CGFloat = AppDesign.cardCornerRadius,
        tint: Color? = nil,
        isInteractive: Bool = false
    ) -> some View {
        modifier(AppGlassSurfaceModifier(cornerRadius: cornerRadius, tint: tint, isInteractive: isInteractive))
    }

    @ViewBuilder
    func appTabBarBehavior() -> some View {
        if #available(iOS 26, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }

    /// Unified camera-style bottom accessory: shop switcher + search button when
    /// there are multiple cafe shops to pick between, or a plain search row
    /// otherwise. Only attach when content is real — an empty
    /// `tabViewBottomAccessory` still draws system glass chrome on every tab.
    @ViewBuilder
    func appCafeBottomAccessory(
        isEnabled: Bool,
        shops: [Shop],
        selectedShopID: Int,
        selectShop: @escaping (Int) -> Void,
        searchAction: @escaping () -> Void
    ) -> some View {
        if #available(iOS 26, *), isEnabled {
            tabViewBottomAccessory {
                CafeBottomAccessory(
                    shops: shops,
                    selectedShopID: selectedShopID,
                    selectShop: selectShop,
                    searchAction: searchAction
                )
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func appScrollEdgeStyle() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        } else {
            self
        }
    }
}

@available(iOS 26, *)
private struct CafeSearchAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if placement == .inline {
                Label("메뉴 검색", systemImage: "magnifyingglass")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
            } else {
                Label("모든 매장의 메뉴 검색", systemImage: "magnifyingglass")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
            }
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
        .accessibilityLabel("메뉴 검색")
        .accessibilityIdentifier("cafe.search.accessory")
    }
}

/// Camera-style bottom row: shop switcher (~3/5 width) centered between two
/// fixed-size glass buttons. `tabViewBottomAccessoryPlacement` tells us
/// whether the GNB is expanded (`.regular`, a full-width row above the tab
/// bar) or minimized (`.inline`, sharing one row with the collapsed GNB
/// pill) — the pill itself is system-drawn and out of our view tree, so we
/// only lay out our own content and let the system dock it beside the pill.
@available(iOS 26, *)
private struct CafeBottomAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    let shops: [Shop]
    let selectedShopID: Int
    let selectShop: (Int) -> Void
    let searchAction: () -> Void

    @State private var isSwitcherEngaged = false

    private var isInline: Bool { placement == .inline }
    private let sideButtonSize: CGFloat = 44

    var body: some View {
        if shops.count > 1 {
            multiShopRow
        } else {
            CafeSearchAccessory(action: searchAction)
        }
    }

    private var multiShopRow: some View {
        HStack(spacing: 8) {
            if !isInline, !isSwitcherEngaged {
                // Balances the search button on the other side so the switcher
                // reads as centered on the full-width expanded-GNB row.
                Color.clear
                    .frame(width: sideButtonSize, height: sideButtonSize)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }

            CafeShopModeSwitcher(
                shops: shops,
                selectedShopID: selectedShopID,
                selectShop: selectShop,
                showsTrackGlass: !isInline,
                isEngaged: $isSwitcherEngaged
            )
            .frame(maxWidth: .infinity)

            if !isSwitcherEngaged {
                searchButton
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .frame(height: sideButtonSize)
    }

    private var searchButton: some View {
        Button(action: searchAction) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .frame(width: sideButtonSize, height: sideButtonSize)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("메뉴 검색")
        .accessibilityIdentifier("cafe.search.accessory")
    }
}

struct AppGlassGroup<Content: View>: View {
    let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

struct AppPrimaryActionButton: View {
    let title: String
    var systemImage: String?
    var isWorking = false
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        if #available(iOS 26, *) {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.borderedProminent)
        }
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isWorking {
                    ProgressView()
                        .accessibilityHidden(true)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .accessibilityValue(isWorking ? "처리 중" : "")
    }
}

struct AppSecondaryActionButton: View {
    let title: String
    var systemImage: String?
    var isWorking = false
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        if #available(iOS 26, *) {
            button.buttonStyle(.glass)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isWorking {
                    ProgressView()
                        .accessibilityHidden(true)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .accessibilityValue(isWorking ? "처리 중" : "")
    }
}

struct AppBottomActionBar<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        AppGlassGroup(spacing: 8) {
            content
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar.opacity(0.001))
    }
}

struct NetworkStatusBanner: View {
    var body: some View {
        Label("오프라인 — 연결되면 다시 시도할 수 있습니다", systemImage: "wifi.slash")
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .appGlassSurface(cornerRadius: 18, tint: .orange)
            .accessibilityAddTraits(.isStaticText)
    }
}
