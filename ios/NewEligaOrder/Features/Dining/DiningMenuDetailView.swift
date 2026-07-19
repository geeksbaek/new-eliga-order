import SwiftUI

struct DiningMenuDetailView: View {
    @Environment(AppStore.self) private var store
    let context: DiningMenuDetailContext
    let transitionNamespace: Namespace.ID
    @State private var resolvedPreparation: DiningMenuPreparation?
    @State private var isPreparing = false

    init(context: DiningMenuDetailContext, transitionNamespace: Namespace.ID) {
        self.context = context
        self.transitionNamespace = transitionNamespace
        _resolvedPreparation = State(initialValue: nil)
    }

    private var meal: DiningMenuItem { context.meal }
    private var title: DiningMenuTitlePresentation { meal.titlePresentation }
    private var displayedSurface: DiningDynamicUISurface? {
        resolvedPreparation?.dynamicSurface ?? context.preparedSurface
    }
    private var personalization: DiningMenuPersonalization? {
        resolvedPreparation?.personalization ?? context.personalization
    }

    var body: some View {
        AppMenuDetailScrollView {
            fixedHeader

            if let displayedSurface {
                DiningDynamicSurfaceView(
                    surface: displayedSurface,
                    personalization: personalization
                )
            } else {
                DiningUnstructuredDetailView(context: context, isPreparing: isPreparing)
            }
        }
        .navigationTitle(title.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: context.preparationKey) {
            guard context.preparedSurface == nil else { return }
            isPreparing = true
            defer { isPreparing = false }
            guard let prepared = try? await store.preparedDiningDay(
                shopID: context.shopID,
                date: context.date
            ), !Task.isCancelled else { return }
            resolvedPreparation = prepared.preparations[context.preparationKey]
        }
    }

    private var fixedHeader: some View {
        AppMenuDetailHeroHeader(
            imageURL: meal.imageURL,
            imageAccessibilityLabel: "\(title.displayName) 메뉴 사진",
            placeholderSystemImage: "fork.knife",
            isUnavailable: context.isSoldOut
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if !title.badges.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(title.badges.enumerated()), id: \.offset) { _, badge in
                            MenuLabelBadge(text: badge, size: .regular)
                        }
                    }
                }

                if let personalization,
                   personalization.recommendation != .neutral || personalization.hasAllergyWarning {
                    HStack(spacing: 6) {
                        DiningPersonalizationLabels(personalization: personalization)
                    }
                }
            }
        }
    }

}

private struct DiningUnstructuredDetailView: View {
    let context: DiningMenuDetailContext
    let isPreparing: Bool

    private var information: String {
        context.meal.information.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            if isPreparing {
                AppMenuDetailSection {
                    HStack(spacing: 12) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("메뉴 정보를 구성하는 중…")
                                .font(.subheadline.weight(.semibold))
                            Text("완료 전까지 원본 정보를 표시합니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            AppMenuDetailSection(title: "메뉴 정보", systemImage: "doc.text") {
                Text(information.isEmpty ? "등록된 상세 정보가 없습니다." : information)
                    .font(.body)
                    .foregroundStyle(information.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            if context.meal.calorie != nil
                || !context.meal.nutrition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !context.origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AppMenuDetailSection(title: "기본 정보", systemImage: "list.bullet") {
                    VStack(spacing: 10) {
                        if let calorie = context.meal.calorie {
                            LabeledContent("열량", value: "\(calorie) kcal")
                        }
                        if !context.meal.nutrition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            LabeledContent("영양", value: context.meal.nutrition)
                        }
                        if !context.origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            LabeledContent("원산지", value: context.origin)
                        }
                    }
                }
            }
        }
    }
}

#if DEBUG
struct DiningMenuDetailFixtureView: View {
    @Namespace private var transitionNamespace

    private let context: DiningMenuDetailContext = {
        let information = """
        [원산지]
        제육볶음
        쌀밥
        된장국
        배추김치
        콩나물무침
        [알러지주의음식]
        대두 포함
        [중식 이용 안내]
        11:30부터 이용 가능합니다
        """
        let sideDishSummary = "쌀밥, 된장국, 배추김치, 콩나물무침"
        let meal = DiningMenuItem(
            name: "[밸런스바이츠] 제육볶음",
            calorie: 650,
            nutrition: "탄수화물 88g / 단백질 27g / 지방 18g / 포화지방 5g / 당류 9g / 식이섬유 7g / 나트륨 1,200mg",
            information: information,
            imageURL: nil,
            isSoldOut: false
        )
        let input = DiningDynamicUIInput(
            menuName: meal.titlePresentation.displayName,
            information: information,
            sideDishSummary: sideDishSummary,
            calorie: meal.calorie,
            nutrition: meal.nutrition,
            origin: "돼지고기 국내산"
        )
        let fallbackSurface = DiningDynamicUIFallback.surface(for: input)
        let nutritionBlock = fallbackSurface.blocks.first(where: { $0.kind == .metrics })
        let duplicatedSurface = DiningDynamicUISurface(
            blocks: fallbackSurface.blocks + (nutritionBlock.map { [$0] } ?? []),
            isModelGenerated: false
        )
        return DiningMenuDetailContext(
            meal: meal,
            sideDishSummary: sideDishSummary,
            courseName: "한식",
            coursePrice: 7_000,
            courseIsSoldOut: false,
            congestion: "NORMAL",
            origin: "돼지고기 국내산",
            periodName: "중식",
            startTime: "11:30:00",
            endTime: "13:30:00",
            date: .now,
            shopID: 7,
            // UI 테스트가 손상된 생성 결과를 재현해 화면 최종 방어선까지 검증한다.
            preparedSurface: duplicatedSurface,
            personalization: DiningMenuPersonalization(
                recommendation: .recommended,
                reason: "쌀밥 선호",
                hasAllergyWarning: false,
                positiveComponents: ["쌀밥"]
            )
        )
    }()

    var body: some View {
        NavigationStack {
            DiningMenuDetailView(context: context, transitionNamespace: transitionNamespace)
        }
    }
}
#endif
