import SwiftUI

struct DiningMenuDetailView: View {
    let context: DiningMenuDetailContext
    let transitionNamespace: Namespace.ID

    @State private var dynamicSurface: DiningDynamicUISurface?
    @State private var resolvedSideDishSummary: String?

    private var meal: DiningMenuItem { context.meal }
    private var title: DiningMenuTitlePresentation { meal.titlePresentation }
    private var displayedSurface: DiningDynamicUISurface {
        dynamicSurface ?? DiningDynamicUIFallback.surface(
            for: dynamicInput(sideDishSummary: resolvedSideDishSummary ?? context.sideDishSummary)
        )
    }

    var body: some View {
        AppMenuDetailScrollView {
            fixedHeader

            DiningDynamicSurfaceView(surface: displayedSurface)
                .contentTransition(.opacity)
        }
        .navigationTitle(title.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .animation(.smooth, value: displayedSurface)
        .task(id: structuringTaskID) {
            await generateDynamicSurface()
        }
    }

    private var fixedHeader: some View {
        AppMenuDetailHeader(
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

                Text(title.displayName)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func generateDynamicSurface() async {
        dynamicSurface = nil
        resolvedSideDishSummary = nil

        let sideDishSummary: String
        if !context.sideDishSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sideDishSummary = context.sideDishSummary
        } else if !meal.information.isEmpty {
            sideDishSummary = await MenuDescriptionSummarizer.shared.summary(
                for: meal.information,
                mode: .diningSideDishes
            )
        } else {
            sideDishSummary = ""
        }

        guard !Task.isCancelled else { return }
        resolvedSideDishSummary = sideDishSummary
        let input = dynamicInput(sideDishSummary: sideDishSummary)
        dynamicSurface = DiningDynamicUIFallback.surface(for: input)

        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        let generated = await DiningMenuDynamicUIStructurer.shared.surface(for: input)
        guard !Task.isCancelled else { return }
        dynamicSurface = generated
    }

    private func dynamicInput(sideDishSummary: String) -> DiningDynamicUIInput {
        DiningDynamicUIInput(
            menuName: title.displayName,
            information: meal.information,
            sideDishSummary: sideDishSummary,
            calorie: meal.calorie,
            nutrition: meal.nutrition,
            origin: context.origin,
            courseName: context.courseName,
            coursePrice: context.coursePrice,
            periodName: context.periodName,
            servingTime: context.servingTime,
            congestion: AppFormat.congestion(context.congestion),
            isSoldOut: context.isSoldOut
        )
    }

    private var structuringTaskID: String {
        [
            meal.id,
            meal.calorie.map(String.init) ?? "",
            meal.nutrition,
            context.sideDishSummary,
            context.origin,
            context.courseName,
            String(context.coursePrice),
            context.periodName,
            context.servingTime,
            context.congestion ?? "",
            String(context.isSoldOut),
        ].joined(separator: "|")
    }
}
