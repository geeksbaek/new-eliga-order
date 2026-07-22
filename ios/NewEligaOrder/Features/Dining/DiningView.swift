import SwiftUI

/// The previous/current/next day around a center date — the sliding window
/// `DiningView`'s day `TabView(.page)` pages through. A pure, testable
/// function so the off-by-one/month-and-year-boundary arithmetic isn't only
/// checked by hand in the simulator.
enum DiningDateWindowPolicy {
    static func window(around date: Date, calendar: Calendar = .autoupdatingCurrent) -> [Date] {
        let start = calendar.startOfDay(for: date)
        return [
            calendar.date(byAdding: .day, value: -1, to: start) ?? start,
            start,
            calendar.date(byAdding: .day, value: 1, to: start) ?? start,
        ]
    }
}

struct DiningView: View {
    @Environment(AppStore.self) private var store
    let shopID: Int
    let transitionNamespace: Namespace.ID
    @State private var date = DiningView.calendar.startOfDay(for: .now)
    @State private var showsPreferences = false

    private static let calendar = Calendar.autoupdatingCurrent

    /// Exactly the previous/current/next day, always centered on `date` —
    /// recomputed fresh on every change (from a swipe or the picker) rather
    /// than tracked as separate state, so there's no window to keep synced
    /// by hand. `ForEach`'s identity diffing (by `Date`, which is `Hashable`)
    /// keeps the two days that carry over between an old and new window
    /// mounted without reloading; only the day that dropped out of range is
    /// torn down and the newly revealed one freshly created.
    private var visibleDates: [Date] {
        DiningDateWindowPolicy.window(around: date, calendar: Self.calendar)
    }

    /// Normalizes every write — from the `DatePicker` or from the `TabView`
    /// settling on a swiped-to page — to the exact start-of-day `Date` used
    /// to build `visibleDates`'s tags, so the two always agree on identity.
    private var dateBinding: Binding<Date> {
        Binding(
            get: { date },
            set: { date = Self.calendar.startOfDay(for: $0) }
        )
    }

    var body: some View {
        // A native paged `TabView` tracks the finger 1:1 during the drag —
        // the adjacent day's menu slides in right alongside it, matching
        // the same live-motion paging CafeView uses for shops.
        TabView(selection: dateBinding) {
            ForEach(visibleDates, id: \.self) { pageDate in
                DiningDayPageView(shopID: shopID, date: pageDate)
                    .tag(pageDate)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle("식단")
        .toolbar {
            ToolbarItem(placement: .principal) {
                DatePicker("날짜", selection: dateBinding, displayedComponents: .date)
                    .labelsHidden()
                    .accessibilityLabel("식단 날짜")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("식단 맞춤 설정", systemImage: "person.crop.circle.badge.checkmark") {
                    showsPreferences = true
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("음식 취향과 알러지 설정")
            }
        }
        .sensoryFeedback(.selection, trigger: date)
        .sheet(isPresented: $showsPreferences) {
            DiningPreferencesSheet(
                currentPreference: store.diningPreferenceText,
                currentAllergies: store.diningAllergies
            ) { preference, allergies in
                store.setDiningPersonalization(preference: preference, allergies: allergies)
            }
            .presentationDetents([.medium, .large])
        }
    }
}

/// One day's full dining page — loading/error/empty states and the meal
/// list — owning its own state so the enclosing `TabView(.page)` can keep
/// each day's page alive and page between them with live, finger-tracked
/// motion.
private struct DiningDayPageView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    let shopID: Int
    let date: Date

    @State private var periods: [DiningPeriod] = []
    @State private var preparations: [String: DiningMenuPreparation] = [:]
    @State private var isLoading = false
    @State private var isPreparing = false
    @State private var errorMessage: String?
    @State private var menuScrollPosition = ScrollPosition(idType: String.self)
    @State private var preferenceFeedbackToken = 0

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
                    if isPreparing {
                        Section {
                            HStack(spacing: 12) {
                                ProgressView()
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("메뉴 정보를 준비하는 중…")
                                        .font(.subheadline.weight(.semibold))
                                    Text("기본 식단은 지금 바로 확인할 수 있어요.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("메뉴 정보를 준비하는 중입니다. 기본 식단은 확인할 수 있습니다.")
                        }
                    }

                    ForEach(periods) { period in
                        Section {
                            ForEach(period.courses) { course in
                                ForEach(course.menus) { meal in
                                    let key = DiningPreparationKey.make(
                                        period: period,
                                        course: course,
                                        meal: meal
                                    )
                                    let preparation = preparations[key]
                                    let personalization = preparation?.personalization ?? .neutral
                                    let context = detailContext(
                                        meal: meal,
                                        preparation: preparation,
                                        course: course,
                                        period: period
                                    )
                                    NavigationLink(value: AppRoute.diningMenu(context: context)) {
                                        DiningMealRow(
                                            meal: meal,
                                            courseName: course.name,
                                            congestion: course.congestion,
                                            isSoldOut: meal.isSoldOut || course.isSoldOut,
                                            sideDishSummary: preparation?.sideDishSummary ?? meal.information,
                                            personalization: personalization
                                        )
                                    }
                                    .id(key)
                                    .listRowBackground(
                                        DiningPersonalizationStyle.background(
                                            for: personalization.recommendation
                                        )
                                    )
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
                                            preferenceFeedbackToken += 1
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
        .task(id: store.diningPersonalizationSignature) {
            // Fires on first appearance (like an unkeyed `.task`) and again
            // whenever personalization changes — `diningDay` and
            // `prepareDiningDay` are already cheap on repeat visits via
            // their own date-keyed and content-keyed caches, so there's no
            // need for an extra "already loaded" guard here.
            await load(replacingContent: true)
        }
        .sensoryFeedback(.selection, trigger: preferenceFeedbackToken)
    }

    private func load(replacingContent: Bool, forceRefresh: Bool = false) async {
        isLoading = true
        isPreparing = false
        if replacingContent {
            periods = []
            preparations = [:]
        }
        defer { isLoading = false }
        errorMessage = nil
        do {
            let rawPeriods = try await store.diningDay(
                shopID: shopID,
                date: date,
                forceRefresh: forceRefresh
            )
            guard !Task.isCancelled else { return }
            periods = rawPeriods
            isLoading = false
            ImagePipeline.shared.preload(
                rawPeriods.flatMap(\.courses).flatMap(\.menus).compactMap(\.imageURL),
                targetSize: 72
            )

            if let cached = await store.cachedPreparedDiningDay(periods: rawPeriods) {
                guard !Task.isCancelled else { return }
                preparations = cached.preparations
                return
            }

            isPreparing = !rawPeriods.isEmpty
            let loaded = await store.prepareDiningDay(periods: rawPeriods)
            guard !Task.isCancelled else { return }
            preparations = loaded.preparations
            isPreparing = false
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func detailContext(
        meal: DiningMenuItem,
        preparation: DiningMenuPreparation?,
        course: DiningCourse,
        period: DiningPeriod
    ) -> DiningMenuDetailContext {
        DiningMenuDetailContext(
            meal: meal,
            sideDishSummary: preparation?.sideDishSummary ?? "",
            courseName: course.name,
            coursePrice: course.price,
            courseIsSoldOut: course.isSoldOut,
            congestion: course.congestion,
            origin: course.origin,
            periodName: period.time,
            startTime: period.startTime,
            endTime: period.endTime,
            date: date,
            shopID: shopID,
            preparedSurface: preparation?.dynamicSurface,
            personalization: preparation?.personalization
        )
    }
}

private extension DiningMenuPersonalization {
    static let neutral = DiningMenuPersonalization(
        recommendation: .neutral,
        reason: nil,
        hasAllergyWarning: false
    )
}

enum DiningPersonalizationStyle {
    /// Row background always stays the plain default surface — it must
    /// never vary by recommendation state, regardless of recommend/avoid/
    /// neutral. Recommendation is communicated only via the chip, not by
    /// tinting the row itself.
    static func background(for recommendation: DiningRecommendationState) -> Color {
        Color(.secondarySystemGroupedBackground)
    }
}

struct DiningPersonalizationLabels: View {
    let personalization: DiningMenuPersonalization

    var body: some View {
        Group {
            switch personalization.recommendation {
            case .recommended:
                iconChip(systemImage: "hand.thumbsup.fill", color: .green)
            case .notRecommended:
                iconChip(systemImage: "hand.thumbsdown.fill", color: .red)
            case .neutral:
                EmptyView()
            }

            if personalization.hasAllergyWarning {
                label("알러지 주의", systemImage: "exclamationmark.triangle.fill", color: .orange)
            }
        }
    }

    /// Recommend/avoid is an icon-only chip (no text) — the surrounding row
    /// already announces "추천 메뉴"/"비추천 메뉴" via its own accessibility
    /// value, so this chip stays hidden from VoiceOver to avoid repeating it.
    private func iconChip(systemImage: String, color: Color) -> some View {
        // Padding matches MenuLabelBadge's compact vertical padding (2pt) —
        // any more and the chip becomes taller than the row's own text,
        // stretching the whole row to fit it.
        Image(systemName: systemImage)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.primary)
            .padding(2)
            .background(color.opacity(0.18), in: Circle())
            .accessibilityHidden(true)
    }

    private func label(_ title: String, systemImage: String, color: Color) -> some View {
        // Built manually instead of `Label` — `Label`'s default icon/title
        // spacing renders noticeably wider than intended for a compact chip.
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.18), in: Capsule())
    }
}

private struct DiningMealRow: View {
    let meal: DiningMenuItem
    let courseName: String
    let congestion: String?
    let isSoldOut: Bool
    let sideDishSummary: String
    let personalization: DiningMenuPersonalization

    private var title: DiningMenuTitlePresentation { meal.titlePresentation }

    var body: some View {
        HStack(alignment: .top) {
            RemoteThumbnail(
                url: meal.imageURL,
                size: 52,
                placeholderSystemImage: "fork.knife"
            )
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(courseName)
                    let congestionLabel = AppFormat.congestion(congestion)
                    if !congestionLabel.isEmpty {
                        Text("·")
                        Text(congestionLabel)
                    }
                    ForEach(Array(title.badges.enumerated()), id: \.offset) { _, badge in
                        MenuLabelBadge(text: badge)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Text(title.displayName)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                    if personalization.recommendation != .neutral || personalization.hasAllergyWarning {
                        DiningPersonalizationLabels(personalization: personalization)
                    }
                }

                if !sideDishSummary.isEmpty {
                    Text(sideDishSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let calorie = meal.calorie {
                    Text("\(calorie) kcal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isSoldOut {
                Text("품절")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.red.opacity(0.14), in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        var values: [String] = []
        switch personalization.recommendation {
        case .recommended: values.append("추천 메뉴")
        case .notRecommended: values.append("비추천 메뉴")
        case .neutral: break
        }
        if personalization.hasAllergyWarning { values.append("알러지 주의") }
        if isSoldOut { values.append("품절") }
        return values.joined(separator: ", ")
    }
}

private struct DiningPreferencesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var preference: String
    @State private var allergies: String
    let save: (String, String) -> Void

    init(
        currentPreference: String,
        currentAllergies: String,
        save: @escaping (String, String) -> Void
    ) {
        _preference = State(initialValue: currentPreference)
        _allergies = State(initialValue: currentAllergies)
        self.save = save
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    AppMenuDetailSection(title: "선호 메뉴·음식 취향", systemImage: "sparkles") {
                    TextField("예: 제육볶음 또는 고기 좋아, 야채 싫어", text: $preference, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(12)
                        .background(
                            Color(.tertiarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .accessibilityIdentifier("dining.preference.input")
                    Text("메뉴명을 입력하거나 평소 음식 취향을 자연어로 설명하세요. 기기에서 식단을 추천·비추천·중립으로 미리 분류합니다.")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    AppMenuDetailSection(title: "나의 알러지", systemImage: "exclamationmark.shield") {
                    TextField("예: 땅콩, 갑각류, 우유", text: $allergies, axis: .vertical)
                        .lineLimit(2...5)
                        .padding(12)
                        .background(
                            Color(.tertiarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .accessibilityIdentifier("dining.allergies.input")
                    Text("관련 가능성이 있는 메뉴에 추천 여부와 별개인 주의 레이블을 표시합니다. 최종 성분은 매장 정보를 다시 확인하세요.")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
                .frame(maxWidth: AppDesign.contentMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .appScrollEdgeStyle()
            .navigationTitle("식단 맞춤 설정")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        save(preference, allergies)
                        dismiss()
                    }
                }
            }
        }
    }
}

#if DEBUG
struct DiningPersonalizationFixtureView: View {
    @State private var showsPreferences = false

    private let rows: [(DiningMenuItem, DiningMenuPersonalization)] = [
        (
            DiningMenuItem(
                name: "제육볶음",
                calorie: 650,
                nutrition: "",
                information: "",
                imageURL: nil,
                isSoldOut: false
            ),
            DiningMenuPersonalization(
                recommendation: .recommended,
                reason: "고기 선호",
                hasAllergyWarning: false
            )
        ),
        (
            DiningMenuItem(
                name: "새우 야채 샐러드",
                calorie: 410,
                nutrition: "",
                information: "",
                imageURL: nil,
                isSoldOut: false
            ),
            DiningMenuPersonalization(
                recommendation: .notRecommended,
                reason: "야채 비선호",
                hasAllergyWarning: true
            )
        ),
        (
            DiningMenuItem(
                name: "두부 된장국",
                calorie: 320,
                nutrition: "",
                information: "",
                imageURL: nil,
                isSoldOut: false
            ),
            DiningMenuPersonalization(
                recommendation: .neutral,
                reason: nil,
                hasAllergyWarning: false
            )
        ),
    ]

    var body: some View {
        NavigationStack {
            List(Array(rows.enumerated()), id: \.offset) { _, row in
                DiningMealRow(
                    meal: row.0,
                    courseName: "중식",
                    congestion: nil,
                    isSoldOut: false,
                    sideDishSummary: row.0.name,
                    personalization: row.1
                )
                .listRowBackground(DiningPersonalizationStyle.background(for: row.1.recommendation))
            }
            .navigationTitle("식단")
            .toolbar {
                Button("식단 맞춤 설정", systemImage: "person.crop.circle.badge.checkmark") {
                    showsPreferences = true
                }
                .accessibilityIdentifier("dining.personalization.settings")
            }
            .sheet(isPresented: $showsPreferences) {
                DiningPreferencesSheet(
                    currentPreference: "고기 좋아, 야채 싫어",
                    currentAllergies: "새우"
                ) { _, _ in }
            }
        }
    }
}
#endif
