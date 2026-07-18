import SwiftUI

struct OrdersView: View {
    @Environment(AppStore.self) private var store
    @State private var sections: [OrderDaySection] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && sections.isEmpty {
                LoadingContentView(title: "주문 내역을 불러오는 중…")
            } else if let errorMessage, sections.isEmpty {
                FailureContentView(message: errorMessage) { Task { await load() } }
            } else if sections.isEmpty {
                ContentUnavailableView(
                    "최근 주문이 없습니다",
                    systemImage: "receipt",
                    description: Text("최근 3개월 동안의 주문이 여기에 표시됩니다.")
                )
            } else {
                List {
                    ForEach(sections) { section in
                        Section(section.title) {
                            ForEach(section.orders) { order in
                                OrderHistoryRow(order: order)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .environment(\.defaultMinListRowHeight, 1)
                .refreshable { await load() }
                .appScrollEdgeStyle()
            }
        }
        .navigationTitle("주문 내역")
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let orders = try await store.api.fetchOrderHistory()
            guard !Task.isCancelled else { return }
            sections = OrderDaySection.make(from: orders)
            await OrderLiveActivityManager.shared.refresh(using: store.api)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct OrderDaySection: Identifiable {
    let id: String
    let title: String
    let date: Date?
    let orders: [OrderHistory]

    @MainActor
    static func make(from orders: [OrderHistory]) -> [OrderDaySection] {
        Dictionary(grouping: orders, by: { AppFormat.orderDayKey($0.orderedAt) })
            .map { key, values in
                let sortedOrders = values.sorted {
                    (AppFormat.orderDate($0.orderedAt) ?? .distantPast)
                        > (AppFormat.orderDate($1.orderedAt) ?? .distantPast)
                }
                let representative = sortedOrders.first?.orderedAt ?? ""
                return OrderDaySection(
                    id: key,
                    title: AppFormat.orderDayTitle(representative),
                    date: AppFormat.orderDate(representative),
                    orders: sortedOrders
                )
            }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
}

private struct OrderHistoryRow: View {
    let order: OrderHistory

    private var itemSummary: String {
        guard let first = order.items.first else { return "주문 항목 없음" }
        let additionalCount = order.items.count - 1
        return additionalCount > 0 ? "\(first.name) 외 \(additionalCount)개" : first.name
    }

    var body: some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                ForEach(Array(order.items.enumerated()), id: \.offset) { index, item in
                    if index > 0 { Divider() }
                    orderLine(item)
                        .padding(.vertical, 10)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(order.shopName.isEmpty ? "엘리가오더" : order.shopName, systemImage: shopSymbol)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Label(AppFormat.orderStatus(order.status), systemImage: statusSymbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .labelStyle(.titleAndIcon)
                }

                Text(itemSummary)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        orderMetadata
                        Spacer(minLength: 8)
                        PriceText(amount: order.totalPaid)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        orderMetadata
                        PriceText(amount: order.totalPaid)
                    }
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
        .tint(.secondary)
    }

    private var orderMetadata: some View {
        HStack(spacing: 5) {
            Text(AppFormat.orderTime(order.orderedAt))
            if !order.orderNumber.isEmpty {
                Text("·")
                Text("주문 \(order.orderNumber)")
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func orderLine(_ item: OrderLine) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                ForEach(item.options, id: \.self) { option in
                    Text(option)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(item.quantity)개")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(AppFormat.won(item.price))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var shopSymbol: String {
        order.shopType.uppercased().contains("CAFE") ? "cup.and.saucer" : "fork.knife"
    }

    private var statusSymbol: String {
        switch order.status {
        case "ORDER_CANCEL", "ORDER_CANCELED", "ORDER_CANCELLED": "xmark.circle.fill"
        case "PICKUP_COMPLETE", "ORDER_COMPLETE": "checkmark.circle.fill"
        default: "clock.fill"
        }
    }

    private var statusColor: Color {
        switch order.status {
        case "ORDER_CANCEL", "ORDER_CANCELED", "ORDER_CANCELLED": .red
        case "PICKUP_COMPLETE", "ORDER_COMPLETE": .green
        default: .orange
        }
    }
}
