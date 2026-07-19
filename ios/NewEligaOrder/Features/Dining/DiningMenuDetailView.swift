import SwiftUI

struct DiningMenuDetailView: View {
    let context: DiningMenuDetailContext
    let transitionNamespace: Namespace.ID

    private var meal: DiningMenuItem { context.meal }
    private var title: DiningMenuTitlePresentation { meal.titlePresentation }
    private var displayedSurface: DiningDynamicUISurface {
        context.preparedSurface ?? DiningDynamicUIFallback.surface(for: dynamicInput)
    }

    var body: some View {
        AppMenuDetailScrollView {
            fixedHeader

            DiningDynamicSurfaceView(surface: displayedSurface)
        }
        .navigationTitle(title.displayName)
        .navigationBarTitleDisplayMode(.inline)
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

                if let personalization = context.personalization,
                   personalization.recommendation != .neutral || personalization.hasAllergyWarning {
                    HStack(spacing: 6) {
                        DiningPersonalizationLabels(personalization: personalization)
                    }
                }
            }
        }
    }

    private var dynamicInput: DiningDynamicUIInput {
        DiningDynamicUIInput(
            menuName: title.displayName,
            information: meal.information,
            sideDishSummary: context.sideDishSummary,
            calorie: meal.calorie,
            nutrition: meal.nutrition,
            origin: context.origin
        )
    }
}

#if DEBUG
struct DiningMenuDetailFixtureView: View {
    @Namespace private var transitionNamespace

    private let context = DiningMenuDetailContext(
        meal: DiningMenuItem(
            name: "[밸런스바이츠] 제육볶음",
            calorie: 650,
            nutrition: "단백질 27g, 나트륨 1200mg",
            information: """
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
            """,
            imageURL: nil,
            isSoldOut: false
        ),
        sideDishSummary: "쌀밥, 된장국, 배추김치, 콩나물무침",
        courseName: "한식",
        coursePrice: 7_000,
        courseIsSoldOut: false,
        congestion: "NORMAL",
        origin: "돼지고기 국내산",
        periodName: "중식",
        startTime: "11:30:00",
        endTime: "13:30:00",
        date: .now
    )

    var body: some View {
        NavigationStack {
            DiningMenuDetailView(context: context, transitionNamespace: transitionNamespace)
        }
    }
}
#endif
