import CryptoKit
import Foundation
import FoundationModels

// MARK: - Declarative generative dining UI

enum DiningDynamicUIBlockKind: String, Codable, CaseIterable, Hashable, Sendable {
    case chips
    case metrics
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

enum DiningDynamicUIDeduplicator {
    static func surface(_ surface: DiningDynamicUISurface) -> DiningDynamicUISurface {
        var blocks: [DiningDynamicUIBlock] = []
        var blockIndexByKind: [DiningDynamicUIBlockKind: Int] = [:]

        for block in surface.blocks {
            let items = uniqueItems(block.items, kind: block.kind)
            if let index = blockIndexByKind[block.kind] {
                let existing = blocks[index]
                blocks[index] = DiningDynamicUIFallback.block(
                    kind: existing.kind,
                    title: existing.title,
                    items: uniqueItems(existing.items + items, kind: existing.kind)
                )
            } else {
                blockIndexByKind[block.kind] = blocks.count
                blocks.append(
                    DiningDynamicUIFallback.block(
                        kind: block.kind,
                        title: block.title,
                        items: items
                    )
                )
            }
        }

        return DiningDynamicUISurface(
            blocks: blocks,
            isModelGenerated: surface.isModelGenerated
        )
    }

    private static func uniqueItems(
        _ items: [DiningDynamicUIItem],
        kind: DiningDynamicUIBlockKind
    ) -> [DiningDynamicUIItem] {
        var seen = Set<String>()
        return items.filter { item in
            let normalizedLabel = DiningDynamicUIFallback.normalized(item.label)
            let normalizedValue = DiningDynamicUIFallback.normalized(item.value)
            let key = kind == .metrics && !normalizedLabel.isEmpty
                ? normalizedLabel
                : "\(normalizedLabel)|\(normalizedValue)"
            return !key.isEmpty && seen.insert(key).inserted
        }
    }
}

struct DiningDynamicUIInput: Hashable, Sendable {
    let menuName: String
    let information: String
    let sideDishSummary: String
    let calorie: Int?
    let nutrition: String
    let origin: String
}

enum DiningDynamicUIFallback {
    static func surface(for input: DiningDynamicUIInput) -> DiningDynamicUISurface {
        var blocks: [DiningDynamicUIBlock] = []

        let resolvedSideDishes = input.sideDishSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let componentNames = resolvedSideDishes.isEmpty
            ? DiningMenuDetailFallback.componentNames(from: input.information)
            : DiningMenuDetailFallback.componentNames(fromSummary: resolvedSideDishes)
        let menuItems = componentNames
            .filter { normalized($0) != normalized(input.menuName) }
            .prefix(12)
            .map { DiningDynamicUIItem(label: "", value: $0, emphasis: .primary) }
        blocks.append(
            block(
                kind: .chips,
                title: "메뉴 구성",
                items: menuItems.isEmpty ? [unavailableItem("메뉴 구성 정보 없음")] : Array(menuItems)
            )
        )

        var nutritionItems: [DiningDynamicUIItem] = []
        if let calorie = input.calorie {
            nutritionItems.append(
                DiningDynamicUIItem(label: "열량", value: "\(calorie) kcal", emphasis: .primary)
            )
        }
        nutritionItems.append(
            contentsOf: DiningMenuDetailFallback
                .nutritionFacts(from: input.nutrition, excludingCalorie: input.calorie != nil)
                .map { DiningDynamicUIItem(label: $0.label, value: $0.value, emphasis: .primary) }
        )
        blocks.append(
            block(
                kind: .metrics,
                title: "영양 정보",
                items: nutritionItems.isEmpty ? [unavailableItem("영양 정보 없음")] : nutritionItems
            )
        )

        let origin = cleaned(input.origin, maximumLength: 600)
        blocks.append(
            block(
                kind: .text,
                title: "원산지",
                items: [
                    origin.isEmpty
                        ? unavailableItem("원산지 정보 없음")
                        : DiningDynamicUIItem(label: "", value: origin, emphasis: .primary),
                ]
            )
        )

        if let allergy = allergyWarning(from: input.information) {
            blocks.append(
                block(
                    kind: .note,
                    title: "알러지 주의 음식",
                    items: [DiningDynamicUIItem(label: "", value: allergy, emphasis: .primary)]
                )
            )
        }

        return DiningDynamicUISurface(blocks: blocks, isModelGenerated: false)
    }

    private static func unavailableItem(_ value: String) -> DiningDynamicUIItem {
        DiningDynamicUIItem(label: "", value: value, emphasis: .primary)
    }

    static func allergyWarning(from information: String) -> String? {
        let lines = normalizedLines(information)
        guard !lines.isEmpty else { return nil }
        var isInAllergySection = false
        var values: [String] = []

        for line in lines {
            if let title = bracketTitle(from: line) {
                let normalizedTitle = normalized(title)
                isInAllergySection = normalizedTitle.contains("알레르") || normalizedTitle.contains("알러")
                continue
            }
            let inlineValue = line.replacingOccurrences(
                of: #"^(알레르기|알러지|알러지주의음식|알레르기주의음식)\s*[:：-]?\s*"#,
                with: "",
                options: .regularExpression
            )
            let isInlineAllergy = inlineValue != line
            guard isInAllergySection || isInlineAllergy else { continue }
            let value = cleaned(inlineValue, maximumLength: 300)
            guard !value.isEmpty, isMeaningfulAllergy(value) else { continue }
            values.append(value)
        }

        let uniqueValues = values.reduce(into: [String]()) { result, value in
            guard !result.contains(value) else { return }
            result.append(value)
        }
        guard !uniqueValues.isEmpty else { return nil }
        return cleaned(uniqueValues.joined(separator: " · "), maximumLength: 700)
    }

    private static func isMeaningfulAllergy(_ value: String) -> Bool {
        let normalizedValue = normalized(value)
        return !["없음", "해당없음", "정보없음", "없습니다", "무"].contains(normalizedValue)
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
        fallback: DiningDynamicUISurface
    ) -> DiningDynamicUISurface {
        let blocks = fallback.blocks.map { fallbackBlock in
            guard let generated = generatedBlocks.first(where: { $0.kind == fallbackBlock.kind }) else {
                return fallbackBlock
            }
            let items = fallbackBlock.items.map { fallbackItem in
                guard let generatedItem = generated.items.first(where: { item in
                    let value = DiningDynamicUIFallback.cleaned(item.value, maximumLength: 180)
                    return !value.isEmpty
                        && isGrounded(value, in: fallbackItem.value)
                        && labelsMatchIfNeeded(
                            generated: item.label,
                            verified: fallbackItem.label,
                            kind: fallbackBlock.kind
                        )
                }) else {
                    return fallbackItem
                }
                return DiningDynamicUIItem(
                    label: fallbackItem.label,
                    value: DiningDynamicUIFallback.cleaned(generatedItem.value, maximumLength: 180),
                    emphasis: fallbackItem.emphasis
                )
            }
            return DiningDynamicUIFallback.block(
                kind: fallbackBlock.kind,
                title: fallbackBlock.title,
                items: fallbackBlock.kind == .metrics ? items : Array(items.prefix(12))
            )
        }
        return DiningDynamicUIDeduplicator.surface(
            DiningDynamicUISurface(blocks: blocks, isModelGenerated: true)
        )
    }

    private static func labelsMatchIfNeeded(
        generated: String,
        verified: String,
        kind: DiningDynamicUIBlockKind
    ) -> Bool {
        guard kind == .metrics else { return true }
        let generatedLabel = DiningDynamicUIFallback.normalized(generated)
        let verifiedLabel = DiningDynamicUIFallback.normalized(verified)
        return !generatedLabel.isEmpty && generatedLabel == verifiedLabel
    }

    private static func isGrounded(_ value: String, in source: String) -> Bool {
        let normalizedValue = DiningDynamicUIFallback.normalized(value)
        let normalizedSource = DiningDynamicUIFallback.normalized(source)
        guard !normalizedValue.isEmpty else { return false }
        return normalizedSource.contains(normalizedValue)
    }
}
