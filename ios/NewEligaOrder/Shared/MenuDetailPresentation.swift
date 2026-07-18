import SwiftUI

struct AppMenuDetailScrollView<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding()
            .frame(maxWidth: AppDesign.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .appScrollEdgeStyle()
    }
}

struct AppMenuDetailHeader<Summary: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let imageURL: URL?
    let imageAccessibilityLabel: String
    let placeholderSystemImage: String
    let isUnavailable: Bool
    private let summary: Summary

    init(
        imageURL: URL?,
        imageAccessibilityLabel: String,
        placeholderSystemImage: String,
        isUnavailable: Bool = false,
        @ViewBuilder summary: () -> Summary
    ) {
        self.imageURL = imageURL
        self.imageAccessibilityLabel = imageAccessibilityLabel
        self.placeholderSystemImage = placeholderSystemImage
        self.isUnavailable = isUnavailable
        self.summary = summary()
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) {
                    thumbnail(size: 144)
                    summary
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    thumbnail(size: 128)
                    summary
                }
            }
        }
        .padding(16)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    private func thumbnail(size: CGFloat) -> some View {
        RemoteThumbnail(
            url: imageURL,
            size: size,
            placeholderSystemImage: placeholderSystemImage,
            cornerRadius: 18
        )
        .accessibilityHidden(false)
        .saturation(isUnavailable ? 0.15 : 1)
        .opacity(isUnavailable ? 0.55 : 1)
        .overlay {
            if isUnavailable {
                Text("품절")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.red, in: Capsule())
            }
        }
        .accessibilityLabel(imageAccessibilityLabel)
        .accessibilityValue(isUnavailable ? "품절" : "")
    }
}

struct AppMenuDetailSection<Content: View>: View {
    let title: String?
    let systemImage: String?
    private let content: Content

    init(
        title: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                } else {
                    Text(title)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }
}

struct DiningDynamicSurfaceView: View {
    let surface: DiningDynamicUISurface

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(surface.blocks) { block in
                DiningDynamicBlockView(block: block)
            }

            if surface.isModelGenerated {
                Label("기기에서 맞춤 구성됨", systemImage: "apple.intelligence")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel("Apple Intelligence를 사용해 기기에서 맞춤 구성됨")
            }
        }
    }
}

private struct DiningDynamicBlockView: View {
    let block: DiningDynamicUIBlock

    @ViewBuilder
    var body: some View {
        switch block.kind {
        case .status:
            DiningDynamicStatusBlock(block: block)
        case .chips:
            DiningDynamicChipsBlock(block: block)
        case .metrics:
            DiningDynamicMetricsBlock(block: block)
        case .facts:
            DiningDynamicFactsBlock(block: block)
        case .note:
            DiningDynamicTextBlock(block: block, isNote: true)
        case .text:
            DiningDynamicTextBlock(block: block, isNote: false)
        }
    }
}

private struct DiningDynamicStatusBlock: View {
    let block: DiningDynamicUIBlock

    private var accent: Color {
        if block.items.contains(where: { $0.emphasis == .critical }) { return .red }
        if block.items.contains(where: { $0.emphasis == .warning }) { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(block.title, systemImage: "clock.badge.checkmark")
                .font(.headline)
                .foregroundStyle(accent)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                ForEach(Array(block.items.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 3) {
                        if !item.label.isEmpty {
                            Text(item.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(item.value)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(itemColor(item.emphasis))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(accent.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct DiningDynamicChipsBlock: View {
    let block: DiningDynamicUIBlock

    var body: some View {
        AppMenuDetailSection(title: block.title, systemImage: "square.grid.2x2") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 8)], spacing: 8) {
                ForEach(Array(block.items.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 3) {
                        if !item.label.isEmpty {
                            Text(item.label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(item.value)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(itemColor(item.emphasis))
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct DiningDynamicMetricsBlock: View {
    let block: DiningDynamicUIBlock

    var body: some View {
        AppMenuDetailSection(title: block.title, systemImage: "chart.bar.xaxis") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                ForEach(Array(block.items.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.value)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(itemColor(item.emphasis))
                            .minimumScaleFactor(0.8)
                        if !item.label.isEmpty {
                            Text(item.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct DiningDynamicFactsBlock: View {
    let block: DiningDynamicUIBlock

    var body: some View {
        AppMenuDetailSection(title: block.title, systemImage: "list.bullet.rectangle") {
            ForEach(Array(block.items.enumerated()), id: \.offset) { index, item in
                if index > 0 { Divider() }
                if item.label.isEmpty {
                    Text(item.value)
                        .foregroundStyle(itemColor(item.emphasis))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    LabeledContent(item.label) {
                        Text(item.value)
                            .foregroundStyle(itemColor(item.emphasis))
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct DiningDynamicTextBlock: View {
    let block: DiningDynamicUIBlock
    let isNote: Bool

    var body: some View {
        AppMenuDetailSection(
            title: block.title,
            systemImage: isNote ? "exclamationmark.bubble" : "text.alignleft"
        ) {
            ForEach(Array(block.items.enumerated()), id: \.offset) { index, item in
                if index > 0 { Divider() }
                VStack(alignment: .leading, spacing: 4) {
                    if !item.label.isEmpty {
                        Text(item.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(item.value)
                        .font(.body)
                        .foregroundStyle(isNote ? Color.orange : itemColor(item.emphasis))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private func itemColor(_ emphasis: DiningDynamicUIEmphasis) -> Color {
    switch emphasis {
    case .primary: .primary
    case .secondary: .secondary
    case .positive: .green
    case .warning: .orange
    case .critical: .red
    }
}
