import Foundation

@MainActor
final class EligaAPI {
    let client: APIClient

    private struct CacheEntry<Value> {
        let value: Value
        let storedAt: Date

        func isFresh(for lifetime: TimeInterval, now: Date = .now) -> Bool {
            now.timeIntervalSince(storedAt) < lifetime
        }
    }

    private struct CafeMenuCacheKey: Hashable {
        let shopID: Int
        let categoryID: Int?
    }

    private var shopsCache: CacheEntry<[Shop]>?
    private var cafePlanCache: [Int: CacheEntry<CafeSalesPlan?>] = [:]
    private var categoryCache: [Int: CacheEntry<[CafeCategory]>] = [:]
    private var cafeMenuCache: [CafeMenuCacheKey: CacheEntry<[CafeMenuItem]>] = [:]
    private var menuDetailCache: [Int: CacheEntry<MenuDetail>] = [:]
    private var diningCache: [String: CacheEntry<[DiningPeriod]>] = [:]
    private var recentOrdersCache: [Int: CacheEntry<[CafeQuickItem]>] = [:]
    private var popularOrdersCache: [Int: CacheEntry<[CafeQuickItem]>] = [:]
    private var paymentReasonCache: [Int: CacheEntry<[PaymentReason]>] = [:]

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func fetchShops(forceRefresh: Bool = false) async throws -> [Shop] {
        if !forceRefresh, let shopsCache, shopsCache.isFresh(for: 15 * 60) {
            return shopsCache.value
        }
        let stale = shopsCache?.value
        do {
            let value = EligaMapper.shops(try await client.request(path: "shop/me"))
            shopsCache = CacheEntry(value: value, storedAt: .now)
            return value
        } catch {
            if let stale, !forceRefresh { return stale }
            throw error
        }
    }

    func fetchCafeSalesPlan(shopID: Int, forceRefresh: Bool = false) async throws -> CafeSalesPlan? {
        if !forceRefresh, let cached = cafePlanCache[shopID], cached.isFresh(for: 30) {
            return cached.value
        }
        let stale = cafePlanCache[shopID]?.value
        do {
            let value = EligaMapper.cafeSalesPlan(
                try await client.request(path: "sales-plan/cafe/\(shopID)"),
                fallbackShopID: shopID
            )
            cafePlanCache[shopID] = CacheEntry(value: value, storedAt: .now)
            return value
        } catch {
            if let stale, !forceRefresh { return stale }
            throw error
        }
    }

    func fetchCafeCategories(shopID: Int, forceRefresh: Bool = false) async throws -> [CafeCategory] {
        if !forceRefresh, let cached = categoryCache[shopID], cached.isFresh(for: 30 * 60) {
            return cached.value
        }
        let stale = categoryCache[shopID]?.value
        do {
            let value = EligaMapper.categories(try await client.request(
                path: "goods/category",
                query: [URLQueryItem(name: "shopId", value: String(shopID))]
            ))
            categoryCache[shopID] = CacheEntry(value: value, storedAt: .now)
            return value
        } catch {
            if let stale, !forceRefresh { return stale }
            throw error
        }
    }

    func fetchCafeMenu(shopID: Int, categoryID: Int? = nil, forceRefresh: Bool = false) async throws -> [CafeMenuItem] {
        let key = CafeMenuCacheKey(shopID: shopID, categoryID: categoryID)
        if !forceRefresh, let cached = cafeMenuCache[key], cached.isFresh(for: 15 * 60) {
            return cached.value
        }
        let stale = cafeMenuCache[key]?.value
        var query = [URLQueryItem(name: "shopId", value: String(shopID))]
        if let categoryID { query.append(URLQueryItem(name: "categoryId", value: String(categoryID))) }
        do {
            async let categoryRequest = fetchCafeCategories(shopID: shopID, forceRefresh: forceRefresh)
            async let menuRequest = client.request(path: "goods/display", query: query)
            let categories = try await categoryRequest
            let raw = try await menuRequest
            let hiddenIDs = Set(categories.filter { !$0.isVisibleOnMobile }.map(\.id))
            let value = EligaMapper.cafeMenu(raw, hiddenCategoryIDs: hiddenIDs)
            cafeMenuCache[key] = CacheEntry(value: value, storedAt: .now)
            return value
        } catch {
            if let stale, !forceRefresh { return stale }
            throw error
        }
    }

    func fetchMenuDetail(displayID: Int, forceRefresh: Bool = false) async throws -> MenuDetail {
        if !forceRefresh, let cached = menuDetailCache[displayID], cached.isFresh(for: 30 * 60) {
            return cached.value
        }
        let stale = menuDetailCache[displayID]?.value
        do {
            let value = EligaMapper.menuDetail(try await client.request(path: "goods/display/\(displayID)"))
            menuDetailCache[displayID] = CacheEntry(value: value, storedAt: .now)
            return value
        } catch {
            if let stale, !forceRefresh { return stale }
            throw error
        }
    }

    func fetchDiningMenu(shopID: Int, date: Date, forceRefresh: Bool = false) async throws -> [DiningPeriod] {
        let dateString = AppFormat.apiDate(date)
        let cacheKey = "\(shopID)|\(dateString)"
        if !forceRefresh, let cached = diningCache[cacheKey], cached.isFresh(for: 10 * 60) {
            return cached.value
        }
        let stale = diningCache[cacheKey]?.value
        do {
            let value = EligaMapper.dining(try await client.request(
                path: "meal/operation-times-and-courses",
                query: [
                    URLQueryItem(name: "shopId", value: String(shopID)),
                    URLQueryItem(name: "startDate", value: dateString),
                    URLQueryItem(name: "endDate", value: dateString),
                ]
            ))
            diningCache[cacheKey] = CacheEntry(value: value, storedAt: .now)
            return value
        } catch {
            if let stale, !forceRefresh { return stale }
            throw error
        }
    }

    func fetchCartSnapshot(shopID: Int) async throws -> CartSnapshot {
        EligaMapper.cartSnapshot(
            try await client.request(
                path: "goods/cart",
                query: [
                    URLQueryItem(name: "shopId", value: String(shopID)),
                    URLQueryItem(name: "cartType", value: "GENERAL"),
                ]
            )
        )
    }

    func fetchCart(shopID: Int) async throws -> Cart {
        try await fetchCartSnapshot(shopID: shopID).cart
    }

    func addToCart(shopID: Int, goodsID: Int, quantity: Int = 1, options: [SelectedOption] = []) async throws {
        let optionJSON = options.map { option in
            JSONValue.object([
                "goodsOptionId": .int(option.optionID),
                "goodsCartItemOptionMenus": .array(
                    option.menuIDs.map { .object(["goodsOptionMenuId": .int($0)]) }
                ),
            ])
        }
        let body: JSONValue = .object([
            "shopId": .int(shopID),
            "cartType": .string("GENERAL"),
            "generalCartId": .null,
            "goodsCartItems": .array([
                .object([
                    "goodsId": .int(goodsID),
                    "goodsQty": .int(max(1, quantity)),
                    "goodsCartItemOptions": .array(optionJSON),
                ]),
            ]),
        ])
        _ = try await client.request(path: "goods/cart", method: "POST", body: body)
    }

    func updateCartQuantity(cartID: Int, itemID: Int, quantity: Int) async throws {
        let body: JSONValue = .object([
            "cartId": .int(cartID),
            "cartItemId": .int(itemID),
            "goodsQty": .int(quantity),
        ])
        _ = try await client.request(path: "goods/cart/quantity", method: "PUT", body: body)
    }

    func deleteCartItems(cartID: Int, itemIDs: [Int]) async throws {
        let body: JSONValue = .object([
            "id": .int(cartID),
            "goodsCartItemIds": .array(itemIDs.map(JSONValue.int)),
        ])
        _ = try await client.request(path: "goods/cart/item", method: "DELETE", body: body)
    }

    func clearCart(shopID: Int) async throws {
        let cart = try await fetchCart(shopID: shopID)
        guard let cartID = cart.id, !cart.items.isEmpty else { return }
        try await deleteCartItems(cartID: cartID, itemIDs: cart.items.map(\.id))
    }

    func fetchPaymentReasons(shopID: Int, forceRefresh: Bool = false) async throws -> [PaymentReason] {
        if !forceRefresh, let cached = paymentReasonCache[shopID], cached.isFresh(for: 60 * 60) {
            return cached.value
        }
        let stale = paymentReasonCache[shopID]?.value
        do {
            let value = EligaMapper.paymentReasons(try await client.request(
                path: "payment/reason",
                query: [URLQueryItem(name: "shopId", value: String(shopID))]
            ))
            paymentReasonCache[shopID] = CacheEntry(value: value, storedAt: .now)
            return value
        } catch {
            if let stale, !forceRefresh { return stale }
            throw error
        }
    }

    func placeOrder(shopID: Int, cart: Cart, paymentReasonID: Int) async throws -> Int? {
        guard let cartID = cart.id, !cart.items.isEmpty else { throw OrderValidationError.emptyCart }
        guard paymentReasonID > 0 else { throw OrderValidationError.paymentReasonRequired }
        let orderItems = cart.items.map { item in
            JSONValue.object([
                "goodsId": .int(item.goodsID),
                "goodsQty": .int(item.quantity),
                "salesPrice": .int(item.lineTotal),
                "unitPrice": .int(item.price),
                "goodsCartItemId": .int(item.id),
                "goodsOrderItemOptions": .array([]),
            ])
        }
        let body: JSONValue = .object([
            "deviceType": .string("MOBILE"),
            "orderType": .string("AUTO"),
            "payType": .string("INTERNAL"),
            "brandCode": .string(APIClient.brandCode),
            "shopId": .int(shopID),
            "cartId": .int(cartID),
            "totalUnitPrice": .int(cart.total),
            "totalSalesPrice": .int(cart.total),
            "totalUsedPoint": .int(0),
            "goodsOrderType": .string("SHOP_PICKUP"),
            "paymentReasonId": .int(paymentReasonID),
            "orderItems": .array(orderItems),
        ])
        let result = try await client.request(path: "goods/order", method: "POST", body: body)
        return result["content"]["orderId"].intValue
            ?? result["content"]["id"].intValue
            ?? result["orderId"].intValue
    }

    func fetchOrderHistory() async throws -> [OrderHistory] {
        let end = Date.now
        let start = Calendar.current.date(byAdding: .month, value: -3, to: end) ?? end
        return EligaMapper.orderHistory(
            try await client.request(
                path: "order/history",
                query: [
                    URLQueryItem(name: "searchStartDate", value: AppFormat.apiDate(start)),
                    URLQueryItem(name: "searchEndDate", value: AppFormat.apiDate(end)),
                ]
            )
        )
    }

    func fetchOrderStatus(orderID: Int) async throws -> OrderStatusSnapshot {
        let raw = try await client.request(path: "goods/order/status/\(orderID)")
        let direct = EligaMapper.orderStatus(raw, fallbackOrderID: orderID)
        if !direct.status.isEmpty { return direct }

        if let history = try await fetchOrderHistory().first(where: { $0.id == orderID }) {
            return OrderStatusSnapshot(
                orderID: history.id,
                orderNumber: history.orderNumber,
                status: history.status
            )
        }
        return direct
    }

    func fetchRecentOrders(shopID: Int, forceRefresh: Bool = false) async throws -> [CafeQuickItem] {
        if !forceRefresh, let cached = recentOrdersCache[shopID], cached.isFresh(for: 3 * 60) {
            return cached.value
        }
        let stale = recentOrdersCache[shopID]?.value
        do {
            let value = EligaMapper.quickItems(try await client.request(path: "goods/order/recent/\(shopID)"))
            recentOrdersCache[shopID] = CacheEntry(value: value, storedAt: .now)
            return value
        } catch {
            if let stale, !forceRefresh { return stale }
            throw error
        }
    }

    func fetchPopularOrders(shopID: Int, forceRefresh: Bool = false) async throws -> [CafeQuickItem] {
        if !forceRefresh, let cached = popularOrdersCache[shopID], cached.isFresh(for: 5 * 60) {
            return cached.value
        }
        let stale = popularOrdersCache[shopID]?.value
        do {
            let value = EligaMapper.quickItems(try await client.request(path: "goods/order/popular/\(shopID)"))
            popularOrdersCache[shopID] = CacheEntry(value: value, storedAt: .now)
            return value
        } catch {
            if let stale, !forceRefresh { return stale }
            throw error
        }
    }

    func clearReadCaches() {
        shopsCache = nil
        cafePlanCache.removeAll()
        categoryCache.removeAll()
        cafeMenuCache.removeAll()
        menuDetailCache.removeAll()
        diningCache.removeAll()
        recentOrdersCache.removeAll()
        popularOrdersCache.removeAll()
        paymentReasonCache.removeAll()
    }
}

enum OrderValidationError: LocalizedError {
    case emptyCart
    case paymentReasonRequired

    var errorDescription: String? {
        switch self {
        case .emptyCart: return "장바구니가 비어 있습니다."
        case .paymentReasonRequired: return "결제 사유를 선택해 주세요."
        }
    }
}

enum EligaMapper {
    static func shops(_ raw: JSONValue) -> [Shop] {
        raw.content.arrayValue.compactMap { value in
            let object = value.objectValue
            guard let id = object["id"]?.intValue else { return nil }
            let rawType = object["type"]?.stringValue.uppercased() ?? ""
            let kind = ShopKind(rawValue: rawType) ?? .unknown
            return Shop(id: id, name: JSONValue.localize(object["name"] ?? .null), kind: kind, isOpen: object["openYn"]?.boolValue ?? false)
        }
    }

    static func categories(_ raw: JSONValue) -> [CafeCategory] {
        raw.content.arrayValue.compactMap { value in
            let object = value.objectValue
            guard let id = object["id"]?.intValue else { return nil }
            return CafeCategory(
                id: id,
                name: JSONValue.localize(object["name"] ?? .null),
                isVisibleOnMobile: object["mobileUseYn"]?.boolValue ?? false,
                goodsCount: object["goodsDisplayCount"]?.intValue ?? 0
            )
        }
    }

    static func cafeMenu(_ raw: JSONValue, hiddenCategoryIDs: Set<Int> = []) -> [CafeMenuItem] {
        raw.content.arrayValue.compactMap { value in
            let item = value.objectValue
            let representative = item["repGoods"]?.objectValue ?? [:]
            guard let displayID = item["id"]?.intValue ?? item["displayId"]?.intValue,
                  !isTestDisplay(item, representative: representative)
            else { return nil }
            let categoryID = categoryID(item)
            if let categoryID, hiddenCategoryIDs.contains(categoryID) { return nil }
            return CafeMenuItem(
                displayID: displayID,
                goodsID: representative["id"]?.intValue,
                name: JSONValue.localize(item["name"] ?? .null),
                categoryID: categoryID,
                category: JSONValue.localize(item["categoryName"] ?? .null),
                price: planPrice(representative["goodsPricePlans"] ?? .null)
                    + (representative["goodsPricePlans"]?.arrayValue.isEmpty == false ? 0 : (item["salePrice"]?.intValue ?? item["price"]?.intValue ?? 0)),
                isSoldOut: representative["soldOutYn"]?.boolValue ?? item["soldOutYn"]?.boolValue ?? false,
                description: nonempty(JSONValue.localize(representative["description"] ?? .null)),
                calorie: representative["calorie"]?.intValue,
                nutrition: nonempty(JSONValue.localize(representative["nutrition"] ?? .null)),
                label: normalizedLabel(item["labelOptionType"]),
                displayName: JSONValue.localize(representative["displayName"] ?? .null),
                thumbnailURL: imageURL(from: [item, representative])
            )
        }
    }

    static func menuDetail(_ raw: JSONValue) -> MenuDetail {
        var content = raw.content
        if let first = content.arrayValue.first { content = first }
        let object = content.objectValue
        let goodsValues: [JSONValue]
        if !object["goods", default: .null].arrayValue.isEmpty {
            goodsValues = object["goods", default: .null].arrayValue
        } else if object["goods"] != nil {
            goodsValues = [object["goods"]!]
        } else {
            goodsValues = []
        }
        var variants = goodsValues.compactMap(goodsVariant)
        let displayThumbnail = imageURL(from: [object]) ?? variants.compactMap(\.thumbnailURL).first
        variants = variants.map { variant in
            GoodsVariant(
                id: variant.id,
                name: variant.name,
                displayName: variant.displayName,
                price: variant.price,
                isSoldOut: variant.isSoldOut,
                description: variant.description,
                calorie: variant.calorie,
                nutrition: variant.nutrition,
                thumbnailURL: variant.thumbnailURL ?? displayThumbnail,
                options: variant.options
            )
        }
        return MenuDetail(
            displayID: object["id"]?.intValue ?? 0,
            shopID: goodsValues.first?["shopId"].intValue,
            label: normalizedLabel(object["labelOptionType"]),
            thumbnailURL: displayThumbnail,
            variants: variants
        )
    }

    static func dining(_ raw: JSONValue) -> [DiningPeriod] {
        raw.content.arrayValue.flatMap { day in
            day["mealOperationTimes"].arrayValue.map { operation in
                let courses = operation["courses"].arrayValue.map { course in
                    DiningCourse(
                        name: JSONValue.localize(course["name"]),
                        price: planPrice(course["pricePlans"]),
                        menus: course["meals"].arrayValue.map { meal in
                            let nutrition = JSONValue.localize(meal["nutrition"])
                            return DiningMenuItem(
                                name: JSONValue.localize(meal["name"]),
                                calorie: meal["calorie"].intValue ?? parseCalories(nutrition),
                                nutrition: nutrition,
                                information: JSONValue.localize(meal["information"]),
                                imageURL: imageURL(from: [meal.objectValue]),
                                isSoldOut: meal["soldOutYn"].boolValue || meal["stockEmptyYn"].boolValue
                            )
                        },
                        isSoldOut: course["soldOutYn"].boolValue,
                        congestion: nonempty(course["congestionType"].stringValue),
                        origin: JSONValue.localize(course["origin"])
                    )
                }
                return DiningPeriod(
                    time: JSONValue.localize(operation["title"]),
                    startTime: operation["startTime"].stringValue,
                    endTime: operation["endTime"].stringValue,
                    courses: courses
                )
            }
        }
    }

    static func cartSnapshot(_ raw: JSONValue) -> CartSnapshot {
        let cartObject = raw.content["cart"].objectValue
        guard !cartObject.isEmpty else { return CartSnapshot(cart: .empty, restoreLines: []) }
        let values = cartObject["goodsCartItems"]?.arrayValue ?? []
        let items = values.compactMap(cartItem)
        let lines = values.compactMap(restoreLine)
        return CartSnapshot(
            cart: Cart(id: cartObject["id"]?.intValue, shopID: cartObject["shopId"]?.intValue, items: items),
            restoreLines: lines
        )
    }

    static func paymentReasons(_ raw: JSONValue) -> [PaymentReason] {
        raw.content.arrayValue.compactMap { value in
            guard value["useYn"] != .bool(false), let id = value["id"].intValue else { return nil }
            return PaymentReason(id: id, reason: JSONValue.localize(value["reason"]))
        }
    }

    static func orderHistory(_ raw: JSONValue) -> [OrderHistory] {
        raw.content.arrayValue.map { row in
            let goods = row["goodsOrderItems"].arrayValue.map(goodsOrderLine)
            let meals = row["mealOrderItems"].arrayValue.map(mealOrderLine)
            let items = goods + meals
            return OrderHistory(
                id: row["orderId"].intValue ?? row["id"].intValue ?? 0,
                orderNumber: row["orderNo"].stringValue.isEmpty ? row["orderId"].stringValue : row["orderNo"].stringValue,
                shopID: row["shopId"].intValue ?? 0,
                shopName: JSONValue.localize(row["shopName"]),
                shopType: row["shopType"].stringValue,
                status: row["status"].stringValue.isEmpty ? row["orderStatus"].stringValue : row["status"].stringValue,
                orderedAt: ["regAt", "createdAt", "orderDate"].map { row[$0].stringValue }.first { !$0.isEmpty } ?? "",
                totalPaid: ["totalPaidPrice", "totalSalesPrice", "totalUnitPrice"].compactMap { row[$0].intValue }.first
                    ?? items.reduce(0) { $0 + $1.price },
                items: items
            )
        }
    }

    static func orderStatus(_ raw: JSONValue, fallbackOrderID: Int) -> OrderStatusSnapshot {
        let status = firstString(
            in: raw,
            keys: ["status", "orderStatus", "goodsOrderStatus", "statusCode"]
        ) ?? (raw.stringValue.isEmpty ? "" : raw.stringValue)
        let orderID = firstInt(in: raw, keys: ["orderId", "id"]) ?? fallbackOrderID
        let orderNumber = firstString(in: raw, keys: ["orderNo", "orderNumber"])
            ?? String(orderID)
        return OrderStatusSnapshot(
            orderID: orderID,
            orderNumber: orderNumber,
            status: status
        )
    }

    static func quickItems(_ raw: JSONValue) -> [CafeQuickItem] {
        raw.content.arrayValue.compactMap { row in
            guard !isTestDisplay(row.objectValue, representative: row.objectValue) else { return nil }
            return CafeQuickItem(
                displayID: row["displayId"].intValue ?? 0,
                goodsID: row["goodsId"].intValue ?? 0,
                name: JSONValue.localize(row["name"]),
                quantity: max(1, row["goodsQty"].intValue ?? 1),
                thumbnailURL: row["thumbnailYn"] == .bool(false) ? nil : mediaURL(row["thumbnail"].stringValue),
                isSoldOut: row["stockEmptyYn"].boolValue || row["isSale"] == .bool(false),
                isOnSale: row["isSale"] != .bool(false),
                lastOrderAt: nonempty(row["lastOrderAt"].stringValue),
                orderCountHint: row["orderCount"].intValue ?? row["goodsQty"].intValue
            )
        }
    }

    private static func firstString(in value: JSONValue, keys: Set<String>) -> String? {
        switch value {
        case .object(let object):
            for key in keys {
                let candidate = object[key]?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !candidate.isEmpty { return candidate }
            }
            for child in object.values {
                if let candidate = firstString(in: child, keys: keys) { return candidate }
            }
        case .array(let array):
            for child in array {
                if let candidate = firstString(in: child, keys: keys) { return candidate }
            }
        default:
            break
        }
        return nil
    }

    private static func firstInt(in value: JSONValue, keys: Set<String>) -> Int? {
        switch value {
        case .object(let object):
            for key in keys {
                if let candidate = object[key]?.intValue { return candidate }
            }
            for child in object.values {
                if let candidate = firstInt(in: child, keys: keys) { return candidate }
            }
        case .array(let array):
            for child in array {
                if let candidate = firstInt(in: child, keys: keys) { return candidate }
            }
        default:
            break
        }
        return nil
    }

    static func cafeSalesPlan(_ raw: JSONValue, fallbackShopID: Int) -> CafeSalesPlan? {
        let value = raw.content
        guard !value.objectValue.isEmpty else { return nil }
        return CafeSalesPlan(
            shopID: value["shopId"].intValue ?? value["id"].intValue ?? fallbackShopID,
            isOpen: value["openYn"].boolValue,
            isBreakTime: value["nowBreakTimeYn"].boolValue,
            isLastOrder: value["nowLastOrderYn"].boolValue,
            autoOpenTime: nonempty(value["autoOpenTime"].stringValue),
            autoCloseTime: nonempty(value["autoCloseTime"].stringValue),
            usesLastOrder: value["lastOrderUseYn"].boolValue,
            lastOrderTime: nonempty(value["lastOrderTime"].stringValue),
            openDays: value["openDay"].arrayValue.map { $0.stringValue.uppercased() },
            isOrderPaused: value["pauseOrderYn"].boolValue
        )
    }

    private static func goodsVariant(_ value: JSONValue) -> GoodsVariant? {
        guard let id = value["id"].intValue else { return nil }
        let options = value["goodsOptions"].arrayValue.compactMap { option -> GoodsOption? in
            guard option["activationType"] != .null, let optionID = option["id"].intValue else { return nil }
            return GoodsOption(
                id: optionID,
                name: JSONValue.localize(option["name"]),
                allowsMultipleSelection: option["multiSelectYn"].boolValue,
                menus: option["goodsOptionMenus"].arrayValue.compactMap { menu in
                    guard let menuID = menu["id"].intValue else { return nil }
                    return OptionMenu(
                        id: menuID,
                        name: JSONValue.localize(menu["name"]),
                        price: planPrice(menu["goodsOptionMenuPrices"], key: "optionPrice")
                    )
                }
            )
        }
        return GoodsVariant(
            id: id,
            name: JSONValue.localize(value["name"]),
            displayName: JSONValue.localize(value["displayName"]),
            price: planPrice(value["goodsPricePlans"]),
            isSoldOut: value["soldOutYn"].boolValue,
            description: nonempty(JSONValue.localize(value["description"])),
            calorie: value["calorie"].intValue,
            nutrition: nonempty(JSONValue.localize(value["nutrition"])),
            thumbnailURL: imageURL(from: [value.objectValue]),
            options: options
        )
    }

    private static func cartItem(_ value: JSONValue) -> CartItem? {
        let detail = value["goodsDetail"]
        guard let id = value["id"].intValue, let goodsID = detail["id"].intValue else { return nil }
        let options = value["goodsCartItemOptions"].arrayValue.flatMap { option in
            option["goodsCartItemOptionMenus"].arrayValue.map { menu in
                CartOption(
                    option: JSONValue.localize(option["goodsOption"]["name"]),
                    value: JSONValue.localize(menu["goodsOptionMenu"]["name"])
                )
            }
        }
        return CartItem(
            id: id,
            goodsID: goodsID,
            name: JSONValue.localize(detail["name"]),
            quantity: value["goodsQty"].intValue ?? 0,
            price: planPrice(detail["goodsPricePlans"]),
            options: options,
            thumbnailURL: imageURL(from: [detail.objectValue, value.objectValue])
        )
    }

    private static func restoreLine(_ value: JSONValue) -> CartRestoreLine? {
        guard let goodsID = value["goodsDetail"]["id"].intValue else { return nil }
        let options = value["goodsCartItemOptions"].arrayValue.compactMap { option -> SelectedOption? in
            let optionID = option["goodsOptionId"].intValue ?? option["goodsOption"]["id"].intValue ?? 0
            let menuIDs = option["goodsCartItemOptionMenus"].arrayValue.compactMap {
                $0["goodsOptionMenuId"].intValue ?? $0["goodsOptionMenu"]["id"].intValue
            }
            guard optionID > 0, !menuIDs.isEmpty else { return nil }
            return SelectedOption(optionID: optionID, menuIDs: menuIDs)
        }
        return CartRestoreLine(goodsID: goodsID, quantity: max(1, value["goodsQty"].intValue ?? 1), options: options)
    }

    private static func goodsOrderLine(_ item: JSONValue) -> OrderLine {
        let options = item["goodsOrderItemOptions"].arrayValue.flatMap { option -> [String] in
            let optionName = JSONValue.localize(option["optionName"])
            return option["optionMenus"].arrayValue.compactMap { menu in
                let menuName = JSONValue.localize(menu["name"])
                guard !menuName.isEmpty else { return nil }
                return optionName.isEmpty ? menuName : "\(optionName): \(menuName)"
            }
        }
        let name = ["name", "displayName", "goodsName"].map { JSONValue.localize(item[$0]) }.first { !$0.isEmpty } ?? "메뉴"
        return OrderLine(
            name: name,
            quantity: max(1, item["goodsQty"].intValue ?? item["qty"].intValue ?? 1),
            price: ["paidPrice", "salesPrice", "unitPrice"].compactMap { item[$0].intValue }.first ?? 0,
            options: options
        )
    }

    private static func mealOrderLine(_ item: JSONValue) -> OrderLine {
        let parts = ["operationTimeTitle", "courseName", "mealName"].map { JSONValue.localize(item[$0]) }.filter { !$0.isEmpty }
        return OrderLine(
            name: parts.joined(separator: " · ").isEmpty ? "식단" : parts.joined(separator: " · "),
            quantity: max(1, item["mealQty"].intValue ?? item["goodsQty"].intValue ?? 1),
            price: ["paidPrice", "salesPrice", "unitPrice"].compactMap { item[$0].intValue }.first ?? 0,
            options: []
        )
    }

    private static func planPrice(_ value: JSONValue, key: String = "price") -> Int {
        let plans = value.arrayValue
        let normal = plans.first { $0["payMethodType"].stringValue == "NORMAL" }?[key].intValue ?? 0
        let discount = plans.first { $0["payMethodType"].stringValue == "IDCARD" }?[key].intValue ?? 0
        return normal - discount
    }

    private static func categoryID(_ item: [String: JSONValue]) -> Int? {
        item["categoryId"]?.intValue
            ?? item["goodsCategoryId"]?.intValue
            ?? item["goodsDisplayCategoryId"]?.intValue
            ?? item["category"]?["id"].intValue
    }

    private static func isTestDisplay(_ item: [String: JSONValue], representative: [String: JSONValue]) -> Bool {
        let testKeys = ["testYn", "isTest", "goodsTestYn", "sampleYn", "demoYn", "dummyYn", "qaYn"]
        if testKeys.contains(where: { item[$0]?.boolValue == true || representative[$0]?.boolValue == true }) { return true }
        let plans = representative["goodsPricePlans"]?.arrayValue ?? item["goodsPricePlans"]?.arrayValue ?? []
        if !plans.isEmpty, plans.allSatisfy({ ($0["price"].intValue ?? 0) <= 0 }) { return true }
        return false
    }

    private static func imageURL(from objects: [[String: JSONValue]]) -> URL? {
        let keys = ["thumbnailPath", "thumbnail", "imagePath", "imageUrl", "filePath", "sharePath"]
        for object in objects {
            for key in keys {
                if let url = mediaURL(object[key]?.stringValue ?? "") { return url }
            }
            let files = object["fileItems"]?.arrayValue ?? []
            for file in files {
                if let url = mediaURL(file["filePath"].stringValue), !file["filePath"].stringValue.isEmpty { return url }
                if let url = mediaURL(file["sharePath"].stringValue), !file["sharePath"].stringValue.isEmpty { return url }
            }
        }
        return nil
    }

    private static func mediaURL(_ path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("https://") || path.hasPrefix("http://") { return URL(string: path) }
        let encoded = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/")
            .compactMap { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }
            .joined(separator: "/")
        return URL(string: "https://kr.object.ncloudstorage.com/eliga-order/\(encoded)")
    }

    private static func normalizedLabel(_ value: JSONValue?) -> String? {
        guard let label = nonempty(value?.stringValue ?? ""), label.uppercased() != "NONE" else { return nil }
        return label
    }

    private static func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseCalories(_ value: String) -> Int? {
        guard let range = value.range(of: #"\d+(?:\.\d+)?\s*k?cal"#, options: .regularExpression) else { return nil }
        let digits = value[range].replacingOccurrences(of: #"[^\d.]"#, with: "", options: .regularExpression)
        return Double(digits).map { Int($0.rounded()) }
    }
}

enum CafeRules {
    private static let dayCodes = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

    static func state(for plan: CafeSalesPlan?, now: Date = .now, calendar: Calendar = .current) -> CafeOrderState {
        guard let plan else { return .checking }
        let hours = hoursLabel(open: plan.autoOpenTime, close: plan.autoCloseTime)
        if plan.isOrderPaused { return .closed(message: "주문이 일시 중지되었습니다. \(hours)") }
        if plan.isBreakTime { return .closed(message: "브레이크 타임입니다. \(hours)") }
        let weekday = calendar.component(.weekday, from: now) - 1
        if !plan.openDays.isEmpty, !plan.openDays.contains(dayCodes[weekday]) {
            return .closed(message: "오늘은 휴무입니다. \(hours)")
        }
        guard plan.isOpen else { return .closed(message: "지금은 주문할 수 없습니다. \(hours)") }
        if plan.usesLastOrder, let cutoff = minutes(plan.lastOrderTime), currentMinutes(now, calendar: calendar) >= cutoff {
            return .closed(message: "라스트 오더가 종료되었습니다. \(hours)")
        }
        return .open(hours: hours)
    }

    static func hoursLabel(open: String?, close: String?) -> String {
        AppFormat.timeRange(start: open, end: close)
    }

    private static func minutes(_ value: String?) -> Int? {
        guard let value else { return nil }
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        return parts[0] * 60 + parts[1]
    }

    private static func currentMinutes(_ date: Date, calendar: Calendar) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
}
