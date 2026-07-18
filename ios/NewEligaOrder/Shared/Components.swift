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
