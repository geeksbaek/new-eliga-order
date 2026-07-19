import Foundation

struct CafeSearchHistoryStore: @unchecked Sendable {
    private enum Constants {
        static let storageKey = "eliga.cafe.search-history.v1"
        static let maximumCount = 10
        static let maximumQueryLength = 80
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func history(accountID: String) -> [String] {
        histories[normalizedAccountID(accountID)] ?? []
    }

    @discardableResult
    func record(_ query: String, accountID: String) -> [String] {
        let normalizedQuery = String(
            query.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(Constants.maximumQueryLength)
        )
        guard !normalizedQuery.isEmpty else { return history(accountID: accountID) }

        let accountKey = normalizedAccountID(accountID)
        var allHistories = histories
        var values = allHistories[accountKey] ?? []
        values.removeAll { $0.compare(normalizedQuery, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        values.insert(normalizedQuery, at: 0)
        values = Array(values.prefix(Constants.maximumCount))
        allHistories[accountKey] = values
        persist(allHistories)
        return values
    }

    private var histories: [String: [String]] {
        guard let data = defaults.data(forKey: Constants.storageKey),
              let values = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return values
    }

    private func persist(_ values: [String: [String]]) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        defaults.set(data, forKey: Constants.storageKey)
    }

    private func normalizedAccountID(_ accountID: String) -> String {
        accountID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
