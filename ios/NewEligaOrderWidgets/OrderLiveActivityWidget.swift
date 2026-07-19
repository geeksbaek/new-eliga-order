import ActivityKit
import SwiftUI
import WidgetKit

struct OrderLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OrderActivityAttributes.self) { context in
            OrderLiveActivityLockScreenView(context: context)
                .activityBackgroundTint(.black.opacity(0.88))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "neweligaorder://orders"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: phaseSymbol(context.state.phase))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(phaseColor(context.state.phase))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.attributes.total > 0 {
                        Text(context.attributes.total, format: .currency(code: "KRW").precision(.fractionLength(0)))
                            .font(.caption.monospacedDigit().weight(.semibold))
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.statusText)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(context.attributes.itemSummary)
                            .font(.subheadline)
                            .lineLimit(1)
                        ProgressView(value: progress(context.state.phase))
                            .tint(phaseColor(context.state.phase))
                    }
                }
            } compactLeading: {
                Image(systemName: phaseSymbol(context.state.phase))
                    .foregroundStyle(phaseColor(context.state.phase))
            } compactTrailing: {
                Text(compactLabel(context.state.phase))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(phaseColor(context.state.phase))
            } minimal: {
                Image(systemName: phaseSymbol(context.state.phase))
                    .foregroundStyle(phaseColor(context.state.phase))
            }
            .keylineTint(phaseColor(context.state.phase))
            .widgetURL(URL(string: "neweligaorder://orders"))
        }
    }

    private func phaseSymbol(_ phase: OrderActivityPhase) -> String {
        switch phase {
        case .submitted: "checkmark.circle.fill"
        case .preparing: "cup.and.saucer.fill"
        case .ready: "bell.fill"
        case .completed: "takeoutbag.and.cup.and.straw.fill"
        case .cancelled: "xmark.circle.fill"
        }
    }

    private func phaseColor(_ phase: OrderActivityPhase) -> Color {
        switch phase {
        case .submitted, .preparing: WidgetPalette.brand
        case .ready: .green
        case .completed: .mint
        case .cancelled: .red
        }
    }

    private func compactLabel(_ phase: OrderActivityPhase) -> String {
        switch phase {
        case .submitted: "접수"
        case .preparing: "준비"
        case .ready: "픽업"
        case .completed: "완료"
        case .cancelled: "취소"
        }
    }

    private func progress(_ phase: OrderActivityPhase) -> Double {
        switch phase {
        case .submitted: 0.2
        case .preparing: 0.55
        case .ready: 0.9
        case .completed: 1
        case .cancelled: 0
        }
    }
}

private struct OrderLiveActivityLockScreenView: View {
    let context: ActivityViewContext<OrderActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "cup.and.saucer.fill")
                    .foregroundStyle(WidgetPalette.brand)
                Text(context.attributes.shopName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("주문 \(context.state.orderNumber)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.statusText)
                        .font(.title3.weight(.bold))
                    Text(context.attributes.itemSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                if context.attributes.total > 0 {
                    Text(context.attributes.total, format: .currency(code: "KRW").precision(.fractionLength(0)))
                        .font(.headline.monospacedDigit())
                }
            }
        }
        .padding(16)
    }
}
