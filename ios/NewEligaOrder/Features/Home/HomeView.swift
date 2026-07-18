import SwiftUI

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var periods: [DiningPeriod] = []
    @State private var recentItems: [HomeRecentItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var featuredPeriod: DiningPeriod? {
        let now = Calendar.current.dateComponents([.hour, .minute], from: .now)
        let currentMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        let timedPeriods = periods.compactMap { period -> (DiningPeriod, Int, Int)? in
            guard let start = minutes(from: period.startTime), let end = minutes(from: period.endTime) else { return nil }
            return (period, start, end)
        }
        return timedPeriods.first { currentMinutes >= $0.1 && currentMinutes <= $0.2 }?.0
            ?? timedPeriods.filter { $0.1 > currentMinutes }.min { $0.1 < $1.1 }?.0
            ?? timedPeriods.max { $0.2 < $1.2 }?.0
            ?? periods.first
    }

    private var dishes: [DiningMenuItem] {
        featuredPeriod?.courses.flatMap(\.menus) ?? []
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    dateHeader

                    if let errorMessage {
                        errorBanner(errorMessage)
                    }

                    diningSection
                    cafeSection
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
                .frame(maxWidth: AppDesign.contentMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .appScrollEdgeStyle()
        }
        .navigationTitle("엘리가오더")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("설정", systemImage: "gearshape") { router.push(.settings, on: .home) }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("설정")
            }
        }
        .refreshable { await load(forceRefresh: true) }
        .task { if periods.isEmpty, recentItems.isEmpty { await load() } }
    }

    private var dateHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(Date.now.formatted(.dateTime.month(.wide).day().weekday(.wide)))
                .font(.headline)
            Text("오늘 이용할 메뉴를 빠르게 확인하세요")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var diningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "오늘의 식단",
                actionTitle: "전체 보기",
                action: { router.switchTo(.dining) }
            )

            VStack(alignment: .leading, spacing: 0) {
                if isLoading && periods.isEmpty {
                    CardLoadingPlaceholder(title: "식단을 확인하는 중…", showsBackground: false)
                } else if let period = featuredPeriod, !dishes.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(period.time.isEmpty ? "식단" : period.time)
                                .font(.headline)
                            if !period.startTime.isEmpty, !period.endTime.isEmpty {
                                Text(AppFormat.timeRange(start: period.startTime, end: period.endTime))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(dishes.count)개 메뉴")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 12)

                    ForEach(Array(dishes.prefix(6).enumerated()), id: \.offset) { index, dish in
                        if index > 0 { Divider() }
                        HStack(spacing: 10) {
                            Image(systemName: isPreferred(dish.titlePresentation.displayName) ? "sparkles" : "fork.knife")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(isPreferred(dish.titlePresentation.displayName) ? .orange : .secondary)
                                .frame(width: 22)
                                .accessibilityHidden(true)
                            HStack(spacing: 5) {
                                ForEach(Array(dish.titlePresentation.badges.enumerated()), id: \.offset) { _, badge in
                                    MenuLabelBadge(text: badge)
                                }
                                Text(dish.titlePresentation.displayName)
                                    .font(.body)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 8)
                            if dish.isSoldOut {
                                Text("품절")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(.red.opacity(0.14), in: Capsule())
                            }
                        }
                        .padding(.vertical, 10)
                        .accessibilityElement(children: .combine)
                    }

                    if dishes.count > 6 {
                        Text("외 \(dishes.count - 6)개 메뉴")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("오늘은 등록된 식단이 없습니다")
                            .font(.headline)
                        Text("다른 날짜의 식단은 식단 탭에서 확인할 수 있습니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var cafeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "최근 카페 주문",
                actionTitle: "메뉴 보기",
                action: { router.switchTo(.cafe) }
            )

            if isLoading && recentItems.isEmpty {
                CardLoadingPlaceholder(title: "최근 주문을 확인하는 중…", rows: 2)
            } else if recentItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "cup.and.saucer")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("최근 카페 주문이 없습니다")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 112)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityElement(children: .combine)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(recentItems) { entry in
                            recentOrderButton(entry)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }

    private func sectionHeader(title: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2.bold())
            Spacer()
            Button(actionTitle, action: action)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("다시 시도") { Task { await load() } }
                .font(.footnote.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func recentOrderButton(_ entry: HomeRecentItem) -> some View {
        Button {
            store.selectShop(entry.shop.id)
            router.switchTo(
                .cafe,
                route: .menu(shopID: entry.shop.id, displayID: entry.item.displayID)
            )
        } label: {
            HStack(spacing: 12) {
                CafeMenuThumbnail(
                    url: entry.item.thumbnailURL,
                    size: 64,
                    isSoldOut: entry.item.isSoldOut
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.item.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(entry.shop.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(width: 264, alignment: .leading)
            .frame(minHeight: 88)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(entry.item.displayID == 0)
        .accessibilityLabel(
            entry.item.isSoldOut
                ? "\(entry.item.name), \(entry.shop.name), 품절"
                : "\(entry.item.name), \(entry.shop.name)"
        )
        .accessibilityHint(
            entry.item.isSoldOut
                ? "메뉴 상세 정보를 엽니다. 현재 품절입니다"
                : "해당 매장의 메뉴 상세를 엽니다"
        )
    }

    private func load(forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        async let diningRequest = store.api.fetchDiningMenu(
            shopID: store.diningShopID,
            date: .now,
            forceRefresh: forceRefresh
        )
        async let cafeRequest = loadCafeRecents(forceRefresh: forceRefresh)

        do {
            let loadedPeriods = try await diningRequest
            periods = DiningMenuFilter.periodsWithMeals(loadedPeriods)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }

        guard !Task.isCancelled else { return }
        let cafeResults = await cafeRequest
        let loaded = cafeResults.flatMap { result in
            result.items.prefix(4).map { HomeRecentItem(shop: result.shop, item: $0) }
        }
        if cafeResults.contains(where: \.succeeded) {
            recentItems = loaded
                .sorted { ($0.item.lastOrderAt ?? "") > ($1.item.lastOrderAt ?? "") }
                .prefix(12)
                .map { $0 }
        } else if !store.cafeShops.isEmpty {
            errorMessage = errorMessage ?? "최근 카페 주문을 불러오지 못했습니다."
        }
        ImagePipeline.shared.preload(recentItems.compactMap(\.item.thumbnailURL), targetSize: 96)
    }

    private func loadCafeRecents(forceRefresh: Bool) async -> [HomeRecentLoadResult] {
        let api = store.api
        return await withTaskGroup(
            of: HomeRecentLoadResult.self,
            returning: [HomeRecentLoadResult].self
        ) { group in
            for shop in store.cafeShops {
                group.addTask {
                    do {
                        let items = try await api.fetchRecentOrders(
                            shopID: shop.id,
                            forceRefresh: forceRefresh
                        )
                        return HomeRecentLoadResult(shop: shop, items: items, succeeded: true)
                    } catch {
                        return HomeRecentLoadResult(shop: shop, items: [], succeeded: false)
                    }
                }
            }
            var results: [HomeRecentLoadResult] = []
            for await result in group { results.append(result) }
            return results
        }
    }

    private func isPreferred(_ name: String) -> Bool {
        store.diningPreferences.contains { name.localizedCaseInsensitiveContains($0) }
    }

    private func minutes(from time: String) -> Int? {
        let components = time.split(separator: ":")
        guard components.count >= 2,
              let hour = Int(components[0]),
              let minute = Int(components[1])
        else { return nil }
        return hour * 60 + minute
    }
}

private struct HomeRecentItem: Identifiable {
    var id: String { "\(shop.id)|\(item.id)" }
    let shop: Shop
    let item: CafeQuickItem
}

private struct HomeRecentLoadResult: Sendable {
    let shop: Shop
    let items: [CafeQuickItem]
    let succeeded: Bool
}
