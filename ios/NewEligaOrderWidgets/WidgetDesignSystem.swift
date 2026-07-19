import SwiftUI
import UIKit
import WidgetKit

enum WidgetPalette {
    /// Dominant background color sampled from the production app icon (#B6574C).
    static let brand = Color(red: 182 / 255, green: 87 / 255, blue: 76 / 255)
    static let brandWarm = Color(red: 231 / 255, green: 166 / 255, blue: 160 / 255)
}

struct WidgetHeader: View {
    let title: String
    let systemImage: String
    var updatedAt: Date?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(WidgetPalette.brand)
                .widgetAccentable()
            Text(title)
                .font(.caption.weight(.bold))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let updatedAt, updatedAt > .distantPast {
                Text(updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct WidgetStatusPill: View {
    let title: String
    let systemImage: String
    var isEmphasized = true

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(isEmphasized ? Color.primary : .secondary)
            .background(
                (isEmphasized ? WidgetPalette.brand : Color.secondary).opacity(0.12),
                in: Capsule()
            )
            .widgetAccentable(isEmphasized)
    }
}

struct WidgetEmptyState: View {
    let title: String
    let message: String
    let systemImage: String
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            Image(systemName: systemImage)
                .font(compact ? .headline : .title2)
                .foregroundStyle(WidgetPalette.brand)
                .widgetAccentable()
            Text(title)
                .font(compact ? .caption.weight(.bold) : .headline)
                .lineLimit(compact ? 1 : 2)
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(compact ? 1 : 2)
            if !compact { Spacer(minLength: 0) }
        }
        .accessibilityElement(children: .combine)
    }
}

struct WidgetThumbnail: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    let item: WidgetCafeItem
    let size: CGFloat
    var cornerRadius: CGFloat = 12

    var body: some View {
        Group {
            if let image = WidgetThumbnailRepository.image(for: item.thumbnailKey),
               renderingMode == .fullColor {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [WidgetPalette.brand.opacity(0.24), WidgetPalette.brandWarm.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(size >= 56 ? .title2 : .body)
                        .foregroundStyle(WidgetPalette.brand)
                        .widgetAccentable()
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

struct WidgetCafeRow: View {
    let item: WidgetCafeItem
    let actionTitle: String
    let actionSystemImage: String
    var metadata: String? = nil
    var thumbnailSize: CGFloat = 38
    var isActionEnabled = true

    var body: some View {
        HStack(spacing: 10) {
            WidgetThumbnail(item: item, size: thumbnailSize, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(metadata ?? item.shopName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            WidgetStatusPill(
                title: actionTitle,
                systemImage: actionSystemImage,
                isEmphasized: isActionEnabled
            )
        }
        .frame(minHeight: max(44, thumbnailSize))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(actionTitle)
    }
}

enum WidgetFormat {
    static func won(_ value: Int) -> String {
        value.formatted(.currency(code: "KRW").precision(.fractionLength(0)))
    }

    static func minutePrecision(_ raw: String) -> String {
        raw.replacingOccurrences(
            of: #"(?<!\d)([01]?\d|2[0-3]):([0-5]\d):[0-5]\d(?:\.\d+)?(?!\d)"#,
            with: "$1:$2",
            options: .regularExpression
        )
    }

    static func timeRange(start: String, end: String) -> String {
        [start, end]
            .map(minutePrecision)
            .filter { !$0.isEmpty }
            .joined(separator: "–")
    }

    static func orderDate(_ rawValue: String?) -> Date? {
        guard let rawValue, !rawValue.isEmpty else { return nil }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = isoFormatter.date(from: rawValue) { return value }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let value = isoFormatter.date(from: rawValue) { return value }

        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy.MM.dd HH:mm"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let value = formatter.date(from: rawValue) { return value }
        }
        return nil
    }

    static func relativeOrderLabel(_ rawValue: String?, relativeTo date: Date) -> String? {
        guard let orderDate = orderDate(rawValue) else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: orderDate, relativeTo: date)
    }
}

private struct EligaWidgetBackground: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if renderingMode == .fullColor {
            ZStack {
                Color(.secondarySystemBackground)
                LinearGradient(
                    colors: [WidgetPalette.brandWarm.opacity(0.15), WidgetPalette.brand.opacity(0.06), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(WidgetPalette.brand.opacity(0.08))
                    .frame(width: 150, height: 150)
                    .blur(radius: 2)
                    .offset(x: 70, y: -80)
            }
        } else {
            Color.clear
        }
    }
}

extension View {
    func eligaWidgetBackground() -> some View {
        containerBackground(for: .widget) {
            EligaWidgetBackground()
        }
    }
}
