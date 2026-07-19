import Foundation

struct CafeMenuOptionSelection: Equatable, Sendable {
    let variantID: Int
    let selectedMenus: [Int: Set<Int>]
}

struct CafeMenuOptionSelectionStore: @unchecked Sendable {
    private enum Constants {
        static let storageKey = "eliga.cafe.menu-option-selections.v1"
        static let maximumRecordCount = 100
    }

    private struct StoredRecord: Codable {
        let variantID: Int
        let choices: [StoredChoice]
        let catalog: CatalogSignature
        let updatedAt: Date
    }

    private struct StoredChoice: Codable, Equatable {
        let optionID: Int
        let menuIDs: [Int]
    }

    private struct CatalogSignature: Codable, Equatable {
        let variants: [VariantSignature]

        init(detail: MenuDetail) {
            variants = detail.variants.map(VariantSignature.init)
        }
    }

    private struct VariantSignature: Codable, Equatable {
        let id: Int
        let name: String
        let displayName: String
        let price: Int
        let options: [OptionSignature]

        init(variant: GoodsVariant) {
            id = variant.id
            name = variant.name
            displayName = variant.displayName
            price = variant.price
            options = variant.options.map(OptionSignature.init)
        }
    }

    private struct OptionSignature: Codable, Equatable {
        let id: Int
        let name: String
        let allowsMultipleSelection: Bool
        let menus: [MenuSignature]

        init(option: GoodsOption) {
            id = option.id
            name = option.name
            allowsMultipleSelection = option.allowsMultipleSelection
            menus = option.menus.map(MenuSignature.init)
        }
    }

    private struct MenuSignature: Codable, Equatable {
        let id: Int
        let name: String
        let price: Int

        init(menu: OptionMenu) {
            id = menu.id
            name = menu.name
            price = menu.price
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func restore(
        accountID: String,
        shopID: Int,
        displayID: Int,
        detail: MenuDetail
    ) -> CafeMenuOptionSelection? {
        let recordKey = recordKey(accountID: accountID, shopID: shopID, displayID: displayID)
        var records = storedRecords
        guard let record = records[recordKey] else { return nil }

        guard record.catalog == CatalogSignature(detail: detail),
              let selection = validatedSelection(from: record, detail: detail)
        else {
            records.removeValue(forKey: recordKey)
            persist(records)
            return nil
        }

        return selection
    }

    func save(
        accountID: String,
        shopID: Int,
        displayID: Int,
        detail: MenuDetail,
        variantID: Int,
        selectedMenus: [Int: Set<Int>]
    ) {
        guard let variant = detail.variants.first(where: { $0.id == variantID }) else { return }

        let choices = variant.options.map { option in
            StoredChoice(optionID: option.id, menuIDs: (selectedMenus[option.id] ?? []).sorted())
        }
        let candidate = StoredRecord(
            variantID: variantID,
            choices: choices,
            catalog: CatalogSignature(detail: detail),
            updatedAt: .now
        )
        guard validatedSelection(from: candidate, detail: detail) != nil else { return }

        var records = storedRecords
        records[recordKey(accountID: accountID, shopID: shopID, displayID: displayID)] = candidate
        if records.count > Constants.maximumRecordCount {
            let overflowCount = records.count - Constants.maximumRecordCount
            for key in records.sorted(by: { $0.value.updatedAt < $1.value.updatedAt }).prefix(overflowCount).map(\.key) {
                records.removeValue(forKey: key)
            }
        }
        persist(records)
    }

    private var storedRecords: [String: StoredRecord] {
        guard let data = defaults.data(forKey: Constants.storageKey),
              let records = try? JSONDecoder().decode([String: StoredRecord].self, from: data)
        else { return [:] }
        return records
    }

    private func persist(_ records: [String: StoredRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Constants.storageKey)
    }

    private func recordKey(accountID: String, shopID: Int, displayID: Int) -> String {
        let normalizedAccountID = accountID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return "\(normalizedAccountID)|\(shopID)|\(displayID)"
    }

    private func validatedSelection(
        from record: StoredRecord,
        detail: MenuDetail
    ) -> CafeMenuOptionSelection? {
        guard let variant = detail.variants.first(where: { $0.id == record.variantID }) else { return nil }
        let optionIDs = Set(variant.options.map(\.id))
        let choiceIDs = record.choices.map(\.optionID)
        guard choiceIDs.count == Set(choiceIDs).count,
              Set(choiceIDs) == optionIDs
        else { return nil }

        var selectedMenus: [Int: Set<Int>] = [:]
        for option in variant.options {
            guard let choice = record.choices.first(where: { $0.optionID == option.id }) else { return nil }
            let selectedIDs = Set(choice.menuIDs)
            let availableIDs = Set(option.menus.map(\.id))
            guard selectedIDs.count == choice.menuIDs.count,
                  selectedIDs.isSubset(of: availableIDs),
                  option.allowsMultipleSelection || selectedIDs.count == 1
            else { return nil }
            selectedMenus[option.id] = selectedIDs
        }

        return CafeMenuOptionSelection(variantID: record.variantID, selectedMenus: selectedMenus)
    }
}
