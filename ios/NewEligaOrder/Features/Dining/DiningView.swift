import SwiftUI

struct DiningView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    let shopID: Int
    let transitionNamespace: Namespace.ID
    @State private var date = Date.now
    @State private var periods: [DiningPeriod] = []
    @State private var sideDishSummaries: [String: String] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showsPreferences = false
    @State private var loadedDateKeys: Set<String> = []
    @State private var menuScrollPosition = ScrollPosition(idType: String.self)

    var body: some View {
        Group {
            if isLoading && periods.isEmpty {
                LoadingContentView(title: "식단을 불러오는 중…")
            } else if let errorMessage, periods.isEmpty {
                FailureContentView(message: errorMessage) { Task { await load(replacingContent: true) } }
            } else if periods.isEmpty {
                ContentUnavailableView("등록된 식단이 없습니다", systemImage: "fork.knife")
            } else {
                List {
                    ForEach(periods) { period in
                        Section {
                            ForEach(period.courses) { course in
                                ForEach(course.menus) { meal in
                                    let summaryKey = sideDishSummaryKey(meal: meal, course: course, period: period)
                                    let context = detailContext(
                                        meal: meal,
                                        sideDishSummary: sideDishSummaries[summaryKey] ?? "",
                                        course: course,
                                        period: period
                                    )
                                    NavigationLink(
                                        value: AppRoute.diningMenu(context: context)
                                    ) {
                                        DiningMealRow(
                                            meal: meal,
                                            courseName: course.name,
                                            congestion: course.congestion,
                                            isSoldOut: meal.isSoldOut || course.isSoldOut,
                                            preferred: isPreferred(meal.titlePresentation.displayName),
                                            onSideDishSummaryResolved: { summary in
                                                guard sideDishSummaries[summaryKey] != summary else { return }
                                                sideDishSummaries[summaryKey] = summary
                                            }
                                        )
                                    }
                                    .id("\(period.id)|\(course.id)|\(meal.id)")
                                    .contextMenu {
                                        Button("상세 보기", systemImage: "info.circle") {
                                            router.push(.diningMenu(context: context), on: .dining)
                                        }

                                        let menuName = meal.titlePresentation.displayName
                                        let isExactPreference = store.hasExactDiningPreference(named: menuName)
                                        Button(
                                            isExactPreference ? "선호 메뉴에서 제거" : "선호 메뉴에 추가",
                                            systemImage: isExactPreference ? "minus.circle" : "sparkles"
                                        ) {
                                            store.toggleDiningPreference(named: menuName)
                                        }
                                    }
                                    .accessibilityHint("메뉴 상세 정보를 엽니다")
                                }
                            }
                        } header: {
                            VStack(alignment: .leading) {
                                Text(period.time)
                                Text(AppFormat.timeRange(start: period.startTime, end: period.endTime))
                                    .font(.caption)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollPosition($menuScrollPosition)
                .refreshable { await load(replacingContent: false, forceRefresh: true) }
                .appScrollEdgeStyle()
            }
        }
        .navigationTitle("식단")
        .toolbar {
            ToolbarItem(placement: .principal) {
                DatePicker("날짜", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .accessibilityLabel("식단 날짜")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("선호 메뉴", systemImage: "sparkles") { showsPreferences = true }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("선호 메뉴 설정")
            }
        }
        .task(id: AppFormat.apiDate(date)) {
            let dateKey = AppFormat.apiDate(date)
            guard !loadedDateKeys.contains(dateKey) else { return }
            await load(replacingContent: true)
        }
        .onChange(of: AppFormat.apiDate(date)) { _, _ in
            menuScrollPosition = ScrollPosition(idType: String.self)
        }
        .sensoryFeedback(.selection, trigger: date)
        .sheet(isPresented: $showsPreferences) {
            DiningPreferencesSheet(current: store.diningPreferences) {
                store.setDiningPreferences($0)
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func load(replacingContent: Bool, forceRefresh: Bool = false) async {
        let requestedDate = AppFormat.apiDate(date)
        isLoading = true
        if replacingContent {
            periods = []
            sideDishSummaries = [:]
        }
        defer {
            if requestedDate == AppFormat.apiDate(date) { isLoading = false }
        }
        errorMessage = nil
        do {
            let loaded = try await store.api.fetchDiningMenu(
                shopID: shopID,
                date: date,
                forceRefresh: forceRefresh
            )
            guard !Task.isCancelled, requestedDate == AppFormat.apiDate(date) else { return }
            periods = DiningMenuFilter.periodsWithMeals(loaded)
            loadedDateKeys.insert(requestedDate)
            ImagePipeline.shared.preload(
                periods.flatMap(\.courses).flatMap(\.menus).compactMap(\.imageURL),
                targetSize: 72
            )
        }
        catch is CancellationError { return }
        catch {
            guard requestedDate == AppFormat.apiDate(date) else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func isPreferred(_ name: String) -> Bool {
        store.diningPreferences.contains { name.localizedCaseInsensitiveContains($0) }
    }

    private func detailContext(
        meal: DiningMenuItem,
        sideDishSummary: String,
        course: DiningCourse,
        period: DiningPeriod
    ) -> DiningMenuDetailContext {
        DiningMenuDetailContext(
            meal: meal,
            sideDishSummary: sideDishSummary,
            courseName: course.name,
            coursePrice: course.price,
            courseIsSoldOut: course.isSoldOut,
            congestion: course.congestion,
            origin: course.origin,
            periodName: period.time,
            startTime: period.startTime,
            endTime: period.endTime,
            date: date
        )
    }

    private func sideDishSummaryKey(
        meal: DiningMenuItem,
        course: DiningCourse,
        period: DiningPeriod
    ) -> String {
        "\(AppFormat.apiDate(date))|\(period.id)|\(course.id)|\(meal.id)"
    }
}

private struct DiningMealRow: View {
    let meal: DiningMenuItem
    let courseName: String
    let congestion: String?
    let isSoldOut: Bool
    let preferred: Bool
    let onSideDishSummaryResolved: (String) -> Void

    private var title: DiningMenuTitlePresentation { meal.titlePresentation }

    var body: some View {
        HStack(alignment: .top) {
            RemoteThumbnail(
                url: meal.imageURL,
                size: 52,
                placeholderSystemImage: "fork.knife"
            )
            VStack(alignment: .leading) {
                HStack(spacing: 6) {
                    Text(courseName)
                    let congestionLabel = AppFormat.congestion(congestion)
                    if !congestionLabel.isEmpty {
                        Text("·")
                        Text(congestionLabel)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    if preferred { Image(systemName: "sparkles").foregroundStyle(.orange).accessibilityLabel("추천") }
                    ForEach(Array(title.badges.enumerated()), id: \.offset) { _, badge in
                        MenuLabelBadge(text: badge)
                    }
                    Text(title.displayName)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                }
                if !meal.information.isEmpty {
                    MenuDescriptionText(
                        text: meal.information,
                        mode: .diningSideDishes,
                        onResolved: onSideDishSummaryResolved
                    )
                }
                if let calorie = meal.calorie { Text("\(calorie) kcal").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            if isSoldOut { Text("품절").font(.caption).foregroundStyle(.red) }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DiningPreferencesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    let save: ([String]) -> Void

    init(current: [String], save: @escaping ([String]) -> Void) {
        _text = State(initialValue: current.joined(separator: ", "))
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("예: 닭갈비, 제육볶음", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("선호 메뉴")
                } footer: {
                    Text("쉼표로 구분하세요. 오늘 식단에서 일치하는 메뉴를 추천으로 표시합니다.")
                }
            }
            .navigationTitle("선호 메뉴")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        save(text.split(separator: ",").map(String.init))
                        dismiss()
                    }
                }
            }
        }
    }
}
