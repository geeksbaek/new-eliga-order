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
            tabBarMinimizeBehavior(.never)
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
        // Matches the GNB's own visual inset (see
        // CafeBottomControlsRow.gnbHorizontalInset) so every bottom action
        // bar's width lines up with the tab bar beneath it.
        .padding(.horizontal, CafeBottomControlsRow.gnbHorizontalInset)
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
