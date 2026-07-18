import CryptoKit
import Foundation
import FoundationModels

// MARK: - Declarative generative dining UI

enum DiningDynamicUIBlockKind: String, Codable, CaseIterable, Sendable {
    case status
    case chips
    case metrics
    case facts
    case note
    case text
}

enum DiningDynamicUIEmphasis: String, Codable, CaseIterable, Sendable {
    case primary
    case secondary
    case positive
    case warning
    case critical
}

struct DiningDynamicUIItem: Hashable, Sendable, Codable {
    let label: String
    let value: String
    let emphasis: DiningDynamicUIEmphasis
}

struct DiningDynamicUIBlock: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let kind: DiningDynamicUIBlockKind
    let title: String
    let items: [DiningDynamicUIItem]
}

struct DiningDynamicUISurface: Hashable, Sendable, Codable {
    let blocks: [DiningDynamicUIBlock]
    let isModelGenerated: Bool
}

struct DiningDynamicUIInput: Hashable, Sendable {
    let menuName: String
    let information: String
    let sideDishSummary: String
    let calorie: Int?
    let nutrition: String
    let origin: String
    let courseName: String
    let coursePrice: Int
    let periodName: String
    let servingTime: String
    let congestion: String
    let isSoldOut: Bool

    var coursePriceText: String {
        coursePrice > 0 ? "\(coursePrice.formatted())원" : ""
    }

    var groundingSource: String {
        [
            menuName,
            information,
            sideDishSummary,
            calorie.map { "\($0) kcal" } ?? "",
            nutrition,
            origin,
            courseName,
            coursePriceText,
            periodName,
            servingTime,
            congestion,
            isSoldOut ? "품절" : "제공 가능",
        ].joined(separator: "\n")
    }
}

enum DiningDynamicUIFallback {
    static func surface(for input: DiningDynamicUIInput) -> DiningDynamicUISurface {
        var blocks: [DiningDynamicUIBlock] = []

        let statusItems = statusItems(for: input)
        if !statusItems.isEmpty {
            blocks.append(block(kind: .status, title: statusTitle(for: input), items: statusItems))
        }

        let resolvedSideDishes = input.sideDishSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let componentNames = resolvedSideDishes.isEmpty
            ? DiningMenuDetailFallback.componentNames(from: input.information)
            : DiningMenuDetailFallback.componentNames(fromSummary: resolvedSideDishes)
        let menuItems = componentNames
            .filter { normalized($0) != normalized(input.menuName) }
            .prefix(12)
            .map { DiningDynamicUIItem(label: "", value: $0, emphasis: .primary) }
        if !menuItems.isEmpty {
            blocks.append(block(kind: .chips, title: "메뉴 구성", items: Array(menuItems)))
        }

        var nutritionItems: [DiningDynamicUIItem] = []
        if let calorie = input.calorie {
            nutritionItems.append(
                DiningDynamicUIItem(label: "열량", value: "\(calorie) kcal", emphasis: .primary)
            )
        }
        nutritionItems.append(
            contentsOf: DiningMenuDetailFallback
                .nutritionFacts(from: input.nutrition, excludingCalorie: input.calorie != nil)
                .map { DiningDynamicUIItem(label: $0.label, value: $0.value, emphasis: .secondary) }
        )
        if !nutritionItems.isEmpty {
            blocks.append(block(kind: .metrics, title: "영양 정보", items: nutritionItems))
        }

        var factItems: [DiningDynamicUIItem] = []
        if !input.courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            factItems.append(DiningDynamicUIItem(label: "코스", value: input.courseName, emphasis: .secondary))
        }
        if input.coursePrice > 0 {
            factItems.append(
                DiningDynamicUIItem(label: "가격", value: input.coursePriceText, emphasis: .primary)
            )
        }
        if !factItems.isEmpty {
            blocks.append(block(kind: .facts, title: "이용 정보", items: factItems))
        }

        let origin = cleaned(input.origin, maximumLength: 600)
        if !origin.isEmpty {
            blocks.append(
                block(
                    kind: .text,
                    title: "원산지",
                    items: [DiningDynamicUIItem(label: "", value: origin, emphasis: .secondary)]
                )
            )
        }

        blocks.append(contentsOf: descriptionBlocks(from: input.information))
        return DiningDynamicUISurface(blocks: Array(blocks.prefix(8)), isModelGenerated: false)
    }

    private static func statusItems(for input: DiningDynamicUIInput) -> [DiningDynamicUIItem] {
        var items = [
            DiningDynamicUIItem(
                label: "상태",
                value: input.isSoldOut ? "품절" : "제공 가능",
                emphasis: input.isSoldOut ? .critical : .positive
            ),
        ]
        if !input.periodName.isEmpty {
            items.append(DiningDynamicUIItem(label: "식사", value: input.periodName, emphasis: .primary))
        }
        if !input.servingTime.isEmpty {
            items.append(DiningDynamicUIItem(label: "시간", value: input.servingTime, emphasis: .secondary))
        }
        if !input.congestion.isEmpty {
            items.append(DiningDynamicUIItem(label: "혼잡도", value: input.congestion, emphasis: .warning))
        }
        return items
    }

    private static func statusTitle(for input: DiningDynamicUIInput) -> String {
        if input.isSoldOut { return "현재 제공 상태" }
        return input.periodName.isEmpty ? "이용 상태" : "\(input.periodName) 이용 안내"
    }

    private static func descriptionBlocks(from information: String) -> [DiningDynamicUIBlock] {
        let lines = normalizedLines(information)
        guard !lines.isEmpty else { return [] }

        var sections: [(title: String, lines: [String])] = []
        var currentTitle = "메뉴 안내"
        var currentLines: [String] = []

        func appendCurrentSection() {
            guard !currentLines.isEmpty else { return }
            sections.append((currentTitle, currentLines))
        }

        for line in lines {
            if let title = bracketTitle(from: line) {
                appendCurrentSection()
                currentTitle = title
                currentLines = []
            } else {
                currentLines.append(line)
            }
        }
        appendCurrentSection()

        return sections.compactMap { section in
            let normalizedTitle = normalized(section.title)
            guard normalizedTitle != "원산지" else { return nil }
            let value = cleaned(section.lines.joined(separator: " · "), maximumLength: 700)
            guard !value.isEmpty else { return nil }
            let kind: DiningDynamicUIBlockKind = normalizedTitle.contains("알레르") || normalizedTitle.contains("알러")
                ? .note
                : .text
            return block(
                kind: kind,
                title: section.title,
                items: [DiningDynamicUIItem(label: "", value: value, emphasis: kind == .note ? .warning : .secondary)]
            )
        }
    }

    private static func normalizedLines(_ rawValue: String) -> [String] {
        rawValue
            .replacingOccurrences(
                of: #"(?i)<br\s*/?>|</p\s*>|</div\s*>|</li\s*>"#,
                with: "\n",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { cleaned($0, maximumLength: 300) }
            .filter { !$0.isEmpty }
    }

    private static func bracketTitle(from line: String) -> String? {
        guard line.hasPrefix("["), line.hasSuffix("]"), line.count > 2 else { return nil }
        let title = line.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    static func block(
        kind: DiningDynamicUIBlockKind,
        title: String,
        items: [DiningDynamicUIItem]
    ) -> DiningDynamicUIBlock {
        let cleanTitle = cleaned(title, maximumLength: 30)
        let identity = ([kind.rawValue, cleanTitle] + items.map { "\($0.label)|\($0.value)" })
            .joined(separator: "|")
        let digest = SHA256.hash(data: Data(identity.utf8))
        let id = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return DiningDynamicUIBlock(id: id, kind: kind, title: cleanTitle, items: items)
    }

    static func cleaned(_ value: String, maximumLength: Int) -> String {
        let normalized = AppFormat.minutePrecision(value)
            .replacingOccurrences(of: #"[\u{0000}-\u{001F}\u{007F}]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(normalized.prefix(maximumLength))
    }

    static func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"[^가-힣A-Za-z0-9%]"#, with: "", options: .regularExpression)
            .lowercased()
    }
}

enum DiningDynamicUINormalizer {
    static func normalize(
        generatedBlocks: [DiningDynamicUIBlock],
        input: DiningDynamicUIInput,
        fallback: DiningDynamicUISurface
    ) -> DiningDynamicUISurface {
        let groundedBlocks = generatedBlocks.prefix(8).compactMap { generated -> DiningDynamicUIBlock? in
            let title = DiningDynamicUIFallback.cleaned(generated.title, maximumLength: 30)
            let items = generated.items.prefix(12).compactMap { item -> DiningDynamicUIItem? in
                let label = DiningDynamicUIFallback.cleaned(item.label, maximumLength: 20)
                let value = DiningDynamicUIFallback.cleaned(item.value, maximumLength: 180)
                guard !value.isEmpty, isGrounded(value, in: input.groundingSource) else { return nil }
                return DiningDynamicUIItem(label: label, value: value, emphasis: item.emphasis)
            }
            guard !title.isEmpty, !items.isEmpty else { return nil }
            return DiningDynamicUIFallback.block(kind: generated.kind, title: title, items: items)
        }

        var merged = groundedBlocks
        for fallbackBlock in fallback.blocks {
            if let index = matchingBlockIndex(for: fallbackBlock, in: merged) {
                var items = merged[index].items
                for fallbackItem in fallbackBlock.items where !contains(fallbackItem, in: items) {
                    items.append(fallbackItem)
                }
                merged[index] = DiningDynamicUIFallback.block(
                    kind: merged[index].kind,
                    title: merged[index].title,
                    items: Array(items.prefix(12))
                )
            } else if merged.count < 8 {
                merged.append(fallbackBlock)
            }
        }

        let unique = merged.reduce(into: [DiningDynamicUIBlock]()) { result, block in
            guard !result.contains(where: { $0.id == block.id }) else { return }
            result.append(block)
        }
        guard !unique.isEmpty else { return fallback }
        return DiningDynamicUISurface(blocks: Array(unique.prefix(8)), isModelGenerated: true)
    }

    private static func matchingBlockIndex(
        for fallbackBlock: DiningDynamicUIBlock,
        in blocks: [DiningDynamicUIBlock]
    ) -> Int? {
        let sameKind = blocks.indices.filter { blocks[$0].kind == fallbackBlock.kind }
        guard fallbackBlock.kind == .text || fallbackBlock.kind == .note else { return sameKind.first }
        return sameKind.first { index in
            fallbackBlock.items.contains { contains($0, in: blocks[index].items) }
        }
    }

    private static func contains(_ expected: DiningDynamicUIItem, in items: [DiningDynamicUIItem]) -> Bool {
        let expectedValue = DiningDynamicUIFallback.normalized(expected.value)
        return items.contains { item in
            let value = DiningDynamicUIFallback.normalized(item.value)
            return !value.isEmpty && (value.contains(expectedValue) || expectedValue.contains(value))
        }
    }

    private static func isGrounded(_ value: String, in source: String) -> Bool {
        let normalizedValue = DiningDynamicUIFallback.normalized(value)
        let normalizedSource = DiningDynamicUIFallback.normalized(source)
        guard !normalizedValue.isEmpty else { return false }
        return normalizedSource.contains(normalizedValue)
    }
}
