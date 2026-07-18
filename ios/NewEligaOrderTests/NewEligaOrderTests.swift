import XCTest
@testable import NewEligaOrder

@MainActor
final class NewEligaOrderTests: XCTestCase {
    func testDiningMenuTitleSeparatesLeadingBadge() {
        let title = DiningMenuTitlePresentation(rawValue: "[밸런스바이츠] 닭가슴살 포케")

        XCTAssertEqual(title.displayName, "닭가슴살 포케")
        XCTAssertEqual(title.badges, ["밸런스바이츠"])
    }

    func testDiningMenuTitleSupportsConsecutiveBadges() {
        let title = DiningMenuTitlePresentation(rawValue: "  [건강식] [NEW] 두부 샐러드  ")

        XCTAssertEqual(title.displayName, "두부 샐러드")
        XCTAssertEqual(title.badges, ["건강식", "NEW"])
    }

    func testDiningMenuTitleLeavesPlainAndMalformedNamesIntact() {
        let plain = DiningMenuTitlePresentation(rawValue: "제육볶음")
        XCTAssertEqual(plain.displayName, "제육볶음")
        XCTAssertTrue(plain.badges.isEmpty)

        let malformed = DiningMenuTitlePresentation(rawValue: "[밸런스바이츠 제육볶음")
        XCTAssertEqual(malformed.displayName, "[밸런스바이츠 제육볶음")
        XCTAssertTrue(malformed.badges.isEmpty)
    }

    func testDiningMenuTitleDoesNotRemoveBadgeWithoutMenuName() {
        let title = DiningMenuTitlePresentation(rawValue: "[밸런스바이츠]")

        XCTAssertEqual(title.displayName, "[밸런스바이츠]")
        XCTAssertTrue(title.badges.isEmpty)
    }

    func testDiningPreferenceToggleMatchesExactNameCaseInsensitively() {
        let initial = ["닭", "제육볶음"]

        XCTAssertTrue(DiningPreferenceRules.containsExact(" 제육볶음 ", in: initial))
        XCTAssertFalse(DiningPreferenceRules.containsExact("닭갈비", in: initial))
        XCTAssertEqual(
            DiningPreferenceRules.toggling("제육볶음", in: initial),
            ["닭"]
        )
        XCTAssertEqual(
            DiningPreferenceRules.toggling(" 닭갈비 ", in: initial),
            ["닭", "제육볶음", "닭갈비"]
        )
    }

    func testCafeMenuDescriptionFallbackBuildsOneLineList() {
        let rawValue = """
        <b>오늘의 반찬</b>
        • 배추김치
        - 멸치볶음
        계란말이
        """

        let result = MenuDescriptionFormatter.fallback(rawValue)

        XCTAssertEqual(result, "오늘의 반찬, 배추김치, 멸치볶음, 계란말이")
        XCTAssertFalse(result.contains("\n"))
        XCTAssertLessThanOrEqual(result.count, MenuDescriptionFormatter.maximumLength)
    }

    func testCafeMenuDescriptionModelOutputRemovesPrefixAndLineBreaks() {
        let result = MenuDescriptionFormatter.normalizedModelOutput(
            "반찬 목록: 김치\n두부조림\n시금치나물",
            fallback: "원문"
        )

        XCTAssertEqual(result, "김치, 두부조림, 시금치나물")
    }

    func testDiningSideDishPromptExcludesNonSideDishCategories() {
        let instructions = MenuDescriptionSummarizationMode.diningSideDishes.instructions

        XCTAssertTrue(instructions.contains("[원산지] 표시 아래"))
        XCTAssertTrue(instructions.contains("한 줄당 반찬 하나"))
        XCTAssertTrue(instructions.contains("산지와 재료 원산지 표기는 제거"))
        XCTAssertTrue(instructions.contains("알레르기 정보, 안내 및 홍보 문구는 제거"))
        XCTAssertTrue(instructions.contains("반찬 정보 없음"))
    }

    func testDiningSideDishSourceStartsBelowOriginMarkerAndPreservesLines() {
        let rawValue = """
        <p>오늘의 식단 설명</p>
        <p>[ 원산지 ]</p>
        <p>배추김치(배추 국내산)</p>
        <p>멸치볶음</p>
        <p>알레르기: 대두 포함</p>
        """

        let source = MenuDescriptionSourceExtractor.source(
            for: rawValue,
            mode: .diningSideDishes
        )

        XCTAssertFalse(source.contains("오늘의 식단 설명"))
        XCTAssertFalse(source.contains("[ 원산지 ]"))
        XCTAssertEqual(
            source.components(separatedBy: .newlines).filter { !$0.isEmpty },
            ["배추김치(배추 국내산)", "멸치볶음", "알레르기: 대두 포함"]
        )
    }

    func testDiningSideDishModeSummarizesShortSingleLineDescriptions() {
        let description = "쌀밥, 된장국, 김치, 멸치볶음"

        XCTAssertTrue(
            MenuDescriptionFormatter.shouldSummarize(
                description,
                mode: .diningSideDishes
            )
        )
        XCTAssertFalse(MenuDescriptionFormatter.shouldSummarize(description))
    }

    func testDiningSideDishRuleParserUsesOnlyOriginSectionFoodLines() {
        let rawValue = """
        오늘의 식단
        [원산지]
        배추김치(배추 국내산)
        멸치볶음
        (돼지고기: 국내산)
        안내: 메뉴는 변경될 수 있습니다
        계란말이
        [알레르기]
        대두
        """

        XCTAssertEqual(
            DiningSideDishRuleParser.summary(from: rawValue),
            "배추김치, 멸치볶음, 계란말이"
        )
    }

    func testDiningSideDishRuleParserDoesNotClaimUnmarkedText() {
        XCTAssertNil(DiningSideDishRuleParser.summary(from: "배추김치\n멸치볶음"))
    }

    func testFoundationModelCoordinatorSerializesRequests() async {
        let coordinator = FoundationModelRequestCoordinator()
        let probe = FoundationModelRequestProbe()

        async let first: Int = try coordinator.perform {
            await probe.begin(1)
            try? await Task.sleep(for: .milliseconds(40))
            await probe.end(1)
            return 1
        }
        async let second: Int = try coordinator.perform {
            await probe.begin(2)
            try? await Task.sleep(for: .milliseconds(10))
            await probe.end(2)
            return 2
        }

        _ = try? await (first, second)
        let maximumConcurrentRequests = await probe.maximumConcurrentRequests
        XCTAssertEqual(maximumConcurrentRequests, 1)
    }

    func testFoundationModelCoordinatorIsolatesInferenceFromCallerCancellation() async {
        let coordinator = FoundationModelRequestCoordinator()
        let probe = FoundationModelCancellationProbe()
        let gate = FoundationModelQueueGate()
        let caller = Task {
            try await coordinator.perform {
                await probe.markStarted()
                await gate.blockUntilReleased()
                await probe.finish(inferenceWasCancelled: Task.isCancelled)
                return 1
            }
        }

        await gate.waitUntilBlocked()
        let cancellationReturned = expectation(description: "취소된 호출자 즉시 반환")
        let observer = Task {
            do {
                _ = try await caller.value
            } catch is CancellationError {
                // expected
            } catch {
                XCTFail("예상하지 못한 오류: \(error)")
            }
            cancellationReturned.fulfill()
        }
        caller.cancel()
        await fulfillment(of: [cancellationReturned], timeout: 0.1)
        await gate.release()
        _ = await observer.result
        try? await Task.sleep(for: .milliseconds(10))
        let result = await probe.result
        XCTAssertEqual(result, false)
    }

    func testFoundationModelCoordinatorSkipsCancelledQueuedInference() async {
        let enqueues = FoundationModelEnqueueProbe()
        let coordinator = FoundationModelRequestCoordinator {
            await enqueues.markEnqueued()
        }
        let gate = FoundationModelQueueGate()
        let calls = FoundationModelCallCounter()
        let first = Task {
            try await coordinator.perform {
                await gate.blockUntilReleased()
                return 1
            }
        }
        await gate.waitUntilBlocked()

        let queued = Task {
            try await coordinator.perform {
                await calls.increment()
                return 2
            }
        }
        await enqueues.wait(for: 2)
        queued.cancel()
        await gate.release()
        _ = try? await first.value

        do {
            _ = try await queued.value
            XCTFail("취소된 대기 요청이 실행되면 안 됩니다.")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("예상하지 못한 오류: \(error)")
        }
        let callCount = await calls.value
        XCTAssertEqual(callCount, 0)
    }

    func testDiningMenuDetailFallbackBuildsStructuredRows() {
        let details = DiningMenuDetailFallback.details(
            menuName: "얼큰돈내장국밥",
            information: """
            [원산지]
            얼큰돈내장국밥
            병천순대찜*들깨초장
            (돼지:국내산)
            부추무침
            쌀밥
            섞박지
            [알러지주의음식]
            알류
            """,
            calorie: 650,
            nutrition: "탄수화물 88g, 단백질: 27g, 나트륨 1200mg"
        )

        XCTAssertEqual(details.menuRows.first, DiningMenuDetailRow(label: "주메뉴", value: "얼큰돈내장국밥"))
        XCTAssertEqual(
            details.menuRows.last,
            DiningMenuDetailRow(label: "구성", value: "병천순대찜 · 들깨초장 · 부추무침 · 쌀밥 · 섞박지")
        )
        XCTAssertEqual(details.nutritionRows.first, DiningMenuDetailRow(label: "열량", value: "650 kcal"))
        XCTAssertTrue(details.nutritionRows.contains(DiningMenuDetailRow(label: "단백질", value: "27g")))
        XCTAssertFalse(details.menuRows.contains(where: { $0.value.contains("알류") }))
        XCTAssertFalse(details.isModelGenerated)
    }

    func testDiningDynamicUIFallbackSelectsComponentsFromAvailableData() {
        let input = dynamicDiningInput()

        let surface = DiningDynamicUIFallback.surface(for: input)

        XCTAssertEqual(
            surface.blocks.map(\.kind),
            [.status, .chips, .metrics, .facts, .text, .note]
        )
        let chipValues = surface.blocks
            .first(where: { $0.kind == .chips })?
            .items.map(\.value)
        XCTAssertEqual(chipValues, ["쌀밥", "된장국", "배추김치", "콩나물무침"])
        XCTAssertFalse(surface.isModelGenerated)
    }

    func testDiningDynamicUINormalizerRejectsHallucinationsAndRestoresRequiredFacts() {
        let input = dynamicDiningInput()
        let fallback = DiningDynamicUIFallback.surface(for: input)
        let generated = DiningDynamicUIBlock(
            id: "generated-chips",
            kind: .chips,
            title: "오늘의 구성",
            items: [
                DiningDynamicUIItem(label: "밥", value: "쌀밥", emphasis: .primary),
                DiningDynamicUIItem(label: "디저트", value: "원문에 없는 초콜릿", emphasis: .primary),
            ]
        )

        let surface = DiningDynamicUINormalizer.normalize(
            generatedBlocks: [generated],
            input: input,
            fallback: fallback
        )
        let allValues = surface.blocks
            .flatMap { $0.items }
            .map { $0.value }
            .joined(separator: " · ")

        XCTAssertFalse(allValues.contains("초콜릿"))
        for expected in ["쌀밥", "된장국", "배추김치", "콩나물무침", "650 kcal", "27g"] {
            XCTAssertTrue(allValues.contains(expected), "\(expected)이 동적 UI에 유지되어야 합니다")
        }
        XCTAssertTrue(surface.isModelGenerated)
    }

    func testDiningDynamicUIInstructionsUseDeclarativeTrustedComponentCatalog() {
        let instructions = DiningMenuDynamicUIStructurer.instructions

        XCTAssertTrue(instructions.contains("UI 컴포넌트 카탈로그"))
        XCTAssertTrue(instructions.contains("원문에 없는 사실"))
        XCTAssertTrue(instructions.contains("메뉴명과 사진은 앱의 고정 헤더"))
        XCTAssertTrue(instructions.contains("모든 항목은 누락하거나 새로 만들지 말고"))
        XCTAssertTrue(instructions.contains("숫자 및 단위는 절대 수정하지 않는다"))
    }

    func testDiningMenuDetailInstructionsRequireGroundedStructuredRows() {
        let instructions = DiningMenuDetailStructurer.instructions

        XCTAssertTrue(instructions.contains("원문에 명시된 내용만 사용"))
        XCTAssertTrue(instructions.contains("[원산지] 아래부터 다음 대괄호 섹션 전"))
        XCTAssertTrue(instructions.contains("모든 음식이 menuRows에 정확히 한 번씩 포함"))
        XCTAssertTrue(instructions.contains("음식을 누락하지 말고"))
        XCTAssertTrue(instructions.contains("nutritionRows"))
        XCTAssertTrue(instructions.contains("값이 없는 영양소는 만들지 않는다"))
    }

    func testDiningMenuDetailMergerRestoresEveryFallbackDishWhenModelReturnsOnlyMain() {
        let fallback = DiningMenuDetailFallback.details(
            menuName: "얼큰돈내장국밥",
            information: """
            [원산지]
            얼큰돈내장국밥
            병천순대찜*들깨초장
            부추무침
            쌀밥
            섞박지
            [알러지주의음식]
            알류
            """,
            calorie: nil,
            nutrition: ""
        )

        let merged = DiningMenuDetailMerger.menuRows(
            menuName: "얼큰돈내장국밥",
            generatedRows: [DiningMenuDetailRow(label: "주메뉴", value: "얼큰돈내장국밥")],
            fallbackRows: fallback.menuRows
        )

        XCTAssertEqual(merged, fallback.menuRows)
    }

    func testDiningMenuDetailMergerKeepsModelCategoriesWithoutDroppingUnclassifiedDishes() {
        let fallbackRows = [
            DiningMenuDetailRow(label: "주메뉴", value: "제육볶음"),
            DiningMenuDetailRow(label: "구성", value: "쌀밥 · 된장국 · 배추김치 · 콩나물무침"),
        ]
        let generatedRows = [
            DiningMenuDetailRow(label: "주메뉴", value: "제육볶음"),
            DiningMenuDetailRow(label: "밥", value: "쌀밥"),
            DiningMenuDetailRow(label: "반찬", value: "배추김치"),
            DiningMenuDetailRow(label: "반찬", value: "원문에 없는 초콜릿"),
        ]

        let merged = DiningMenuDetailMerger.menuRows(
            menuName: "제육볶음",
            generatedRows: generatedRows,
            fallbackRows: fallbackRows
        )
        let allValues = merged.map(\.value).joined(separator: " · ")

        for expected in ["쌀밥", "된장국", "제육볶음", "배추김치", "콩나물무침"] {
            XCTAssertTrue(allValues.contains(expected), "\(expected)이 유지되어야 합니다")
        }
        XCTAssertFalse(allValues.contains("초콜릿"))
    }

    func testDiningMenuDetailUsesResolvedListSideDishesAsAuthoritativeComponents() {
        let details = DiningMenuDetailFallback.details(
            menuName: "제육볶음",
            information: """
            [원산지]
            원문 파싱에서 제외되어야 할 항목
            [알레르기]
            대두
            """,
            calorie: nil,
            nutrition: "",
            sideDishSummary: "쌀밥, 된장국, 배추김치, 콩나물무침"
        )

        XCTAssertEqual(
            details.menuRows,
            [
                DiningMenuDetailRow(label: "주메뉴", value: "제육볶음"),
                DiningMenuDetailRow(label: "구성", value: "쌀밥 · 된장국 · 배추김치 · 콩나물무침"),
            ]
        )
    }

    func testDiningMenuDetailMergerRestoresMissingFallbackNutritionRows() {
        let merged = DiningMenuDetailMerger.nutritionRows(
            generatedRows: [DiningMenuDetailRow(label: "열량", value: "추측값")],
            fallbackRows: [
                DiningMenuDetailRow(label: "열량", value: "650 kcal"),
                DiningMenuDetailRow(label: "단백질", value: "27g"),
            ]
        )

        XCTAssertEqual(merged.first, DiningMenuDetailRow(label: "열량", value: "650 kcal"))
        XCTAssertTrue(merged.contains(DiningMenuDetailRow(label: "단백질", value: "27g")))
    }

    func testKeychainPersistsAuthenticationTokensAcrossStoreInstances() throws {
        let service = "com.leeari95.NewEligaOrder.tests.\(UUID().uuidString)"
        let firstStore = KeychainStore(service: service, account: "auth")
        defer { firstStore.clear() }
        let expected = AuthTokens(
            accessToken: "persisted.header.payload",
            refreshToken: "persisted-refresh-token",
            tokenType: "Bearer"
        )

        try firstStore.save(tokens: expected)
        let restored = KeychainStore(service: service, account: "auth").loadTokens()

        XCTAssertEqual(restored?.accessToken, expected.accessToken)
        XCTAssertEqual(restored?.refreshToken, expected.refreshToken)
        XCTAssertEqual(restored?.tokenType, expected.tokenType)
    }

    func testExtractsNestedAuthenticationTokens() {
        let json: JSONValue = .object([
            "content": .object([
                "token": .object([
                    "accessToken": .string("header.payload.signature"),
                    "refreshToken": .string("refresh-token"),
                ]),
            ]),
        ])

        let tokens = APIClient.extractTokens(from: json)

        XCTAssertEqual(tokens?.accessToken, "header.payload.signature")
        XCTAssertEqual(tokens?.refreshToken, "refresh-token")
        XCTAssertEqual(tokens?.tokenType, "Bearer")
    }

    func testExtractsCookieAccessTokenAndResponseRefreshToken() throws {
        let json: JSONValue = .object([
            "content": .object([
                "refreshToken": .string("refresh-from-response"),
            ]),
        ])
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "svc.eligaorder.com",
            .path: "/",
            .name: "AccessToken",
            .value: "cookie.header.payload",
            .secure: "TRUE",
        ]))

        let tokens = APIClient.extractTokens(from: json, cookies: [cookie])

        XCTAssertEqual(tokens?.accessToken, "cookie.header.payload")
        XCTAssertEqual(tokens?.refreshToken, "refresh-from-response")
        XCTAssertEqual(tokens?.tokenType, "Bearer")
    }

    func testRefreshCookieIsUsedWhenResponseOmitsRefreshToken() throws {
        let json: JSONValue = .object([
            "content": .object([
                "accessToken": .string("response.header.payload"),
            ]),
        ])
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: ".eligaorder.com",
            .path: "/",
            .name: "RefreshToken",
            .value: "refresh-from-cookie",
            .secure: "TRUE",
        ]))

        let tokens = APIClient.extractTokens(from: json, cookies: [cookie])

        XCTAssertEqual(tokens?.accessToken, "response.header.payload")
        XCTAssertEqual(tokens?.refreshToken, "refresh-from-cookie")
    }

    func testMapsLocalizedShopsAndNormalizesKinds() {
        let json: JSONValue = .object([
            "content": .array([
                .object([
                    "id": .int(5),
                    "name": .object(["ko": .string("kafé 5F"), "en": .string("Cafe")]),
                    "type": .string("CAFE"),
                    "openYn": .bool(true),
                ]),
            ]),
        ])

        let shops = EligaMapper.shops(json)

        XCTAssertEqual(shops.first?.name, "kafé 5F")
        XCTAssertEqual(shops.first?.kind, .cafe)
        XCTAssertEqual(shops.first?.canOrder, true)
    }

    func testCartTotalsIncludeQuantity() {
        let item = CartItem(
            id: 1,
            goodsID: 10,
            name: "아메리카노",
            quantity: 3,
            price: 1_500,
            options: [],
            thumbnailURL: nil
        )
        let cart = Cart(id: 2, shopID: 5, items: [item])

        XCTAssertEqual(cart.itemCount, 3)
        XCTAssertEqual(cart.total, 4_500)
    }

    func testCafeRulesBlockPausedOrders() {
        let plan = CafeSalesPlan(
            shopID: 5,
            isOpen: true,
            isBreakTime: false,
            isLastOrder: false,
            autoOpenTime: "09:00:00",
            autoCloseTime: "19:00:00",
            usesLastOrder: false,
            lastOrderTime: nil,
            openDays: [],
            isOrderPaused: true
        )

        let state = CafeRules.state(for: plan)

        XCTAssertFalse(state.isOrderable)
        guard case .closed(let message) = state else { return XCTFail("closed 상태여야 합니다") }
        XCTAssertTrue(message.contains("일시 중지"))
        XCTAssertTrue(message.contains("09:00–19:00"))
        XCTAssertFalse(message.contains("09:00:00"))
    }

    func testTimePresentationRemovesSecondsFromRangesAndEmbeddedText() {
        XCTAssertEqual(
            AppFormat.timeRange(start: "07:30:00", end: "09:05:59"),
            "07:30–09:05"
        )
        XCTAssertEqual(
            AppFormat.minutePrecision("운영 시간 09:00:00~18:30:45 안내"),
            "운영 시간 09:00~18:30 안내"
        )
    }

    func testRouterHandlesNativeDeepLinks() throws {
        let router = AppRouter()
        let appURL = try XCTUnwrap(URL(string: "neweligaorder://cafe"))
        let webURL = try XCTUnwrap(URL(string: "https://example.com/cart"))

        XCTAssertTrue(router.handle(url: appURL))
        XCTAssertEqual(router.selectedTab, .cafe)
        XCTAssertFalse(router.handle(url: webURL))
    }

    func testRouterHandlesWidgetMenuAndQuickOrderLinks() throws {
        let router = AppRouter()
        let menuURL = try XCTUnwrap(URL(string: "neweligaorder://menu?shopID=5&displayID=42"))
        let quickURL = try XCTUnwrap(URL(string: "neweligaorder://quick-order?shopID=5&displayID=42"))

        XCTAssertTrue(router.handle(url: menuURL))
        XCTAssertEqual(router.selectedTab, .cafe)
        XCTAssertEqual(router.cafePath, [.menu(shopID: 5, displayID: 42)])

        XCTAssertTrue(router.handle(url: quickURL))
        XCTAssertEqual(router.cafePath, [.quickOrder(shopID: 5, displayID: 42)])
    }

    func testCafeMenuSearchMatchesLocalizedFields() {
        let item = CafeMenuItem(
            displayID: 1,
            goodsID: 2,
            name: "제주 말차 라떼",
            categoryID: 3,
            category: "시즌 음료",
            price: 4_500,
            isSoldOut: false,
            description: "진한 녹차와 우유",
            calorie: nil,
            nutrition: nil,
            label: "NEW",
            displayName: "말차라떼",
            thumbnailURL: nil
        )

        XCTAssertTrue(item.matches(search: "말차"))
        XCTAssertTrue(item.matches(search: "녹차"))
        XCTAssertTrue(item.matches(search: "시즌"))
        XCTAssertFalse(item.matches(search: "아메리카노"))
    }

    func testCafeMenuSearchIgnoresSelectedCategory() {
        let coffee = CafeMenuItem(
            displayID: 1,
            goodsID: 11,
            name: "아메리카노",
            categoryID: 10,
            category: "커피",
            price: 3_000,
            isSoldOut: false,
            description: nil,
            calorie: nil,
            nutrition: nil,
            label: nil,
            displayName: "아메리카노",
            thumbnailURL: nil
        )
        let tea = CafeMenuItem(
            displayID: 2,
            goodsID: 22,
            name: "제주 말차 라떼",
            categoryID: 20,
            category: "티",
            price: 4_500,
            isSoldOut: false,
            description: nil,
            calorie: nil,
            nutrition: nil,
            label: nil,
            displayName: "말차라떼",
            thumbnailURL: nil
        )

        let results = CafeMenuFilter.items(
            in: [coffee, tea],
            selectedCategoryID: coffee.categoryID,
            searchText: "말차"
        )

        XCTAssertEqual(results.map(\.displayID), [tea.displayID])
    }

    func testCafeMenuSearchCombinesEveryShop() {
        let shops = [
            Shop(id: 5, name: "1층 카페", kind: .cafe, isOpen: true),
            Shop(id: 6, name: "5층 카페", kind: .cafe, isOpen: true),
        ]
        let first = CafeMenuItem(
            displayID: 10,
            goodsID: 101,
            name: "아이스 아메리카노",
            categoryID: 1,
            category: "커피",
            price: 2_500,
            isSoldOut: false,
            description: nil,
            calorie: nil,
            nutrition: nil,
            label: nil,
            displayName: "아메리카노",
            thumbnailURL: nil
        )
        let second = CafeMenuItem(
            displayID: 20,
            goodsID: 202,
            name: "디카페인 아메리카노",
            categoryID: 2,
            category: "디카페인",
            price: 3_000,
            isSoldOut: false,
            description: nil,
            calorie: nil,
            nutrition: nil,
            label: nil,
            displayName: "디카페인",
            thumbnailURL: nil
        )

        let sections = CafeMenuFilter.sections(
            shops: shops,
            menusByShop: [5: [first], 6: [second]],
            searchText: "아메리카노"
        )

        XCTAssertEqual(sections.map(\.shop.id), [5, 6])
        XCTAssertEqual(sections.flatMap(\.items).map(\.displayID), [10, 20])
    }

    func testCafeMenuPriorityOrdersFavoritesThenBestThenNew() {
        let regular = cafeMenuItem(displayID: 1, name: "일반", label: nil)
        let new = cafeMenuItem(displayID: 2, name: "신메뉴", label: "new")
        let best = cafeMenuItem(displayID: 3, name: "인기", label: " BEST ")
        let favorite = cafeMenuItem(displayID: 4, name: "즐겨찾기", label: nil)
        let favoriteNew = cafeMenuItem(displayID: 5, name: "즐겨찾기 신메뉴", label: "NEW")

        let results = CafeMenuFilter.items(
            in: [regular, new, best, favorite, favoriteNew],
            selectedCategoryID: nil,
            searchText: "",
            favoriteDisplayIDs: [favorite.displayID, favoriteNew.displayID]
        )

        XCTAssertEqual(results.map(\.displayID), [4, 5, 3, 2, 1])
    }

    func testCafeMenuPriorityPreservesOrderWithinSameGroup() {
        let firstBest = cafeMenuItem(displayID: 10, name: "첫 번째 BEST", label: "BEST")
        let secondBest = cafeMenuItem(displayID: 11, name: "두 번째 BEST", label: "best")
        let firstRegular = cafeMenuItem(displayID: 12, name: "첫 번째 일반", label: nil)
        let secondRegular = cafeMenuItem(displayID: 13, name: "두 번째 일반", label: nil)

        let results = CafeMenuFilter.prioritized(
            [firstRegular, firstBest, secondRegular, secondBest],
            favoriteDisplayIDs: []
        )

        XCTAssertEqual(results.map(\.displayID), [10, 11, 12, 13])
    }

    func testCafeMenuPrioritySectionsSeparateFavoriteBestNewAndStandard() {
        let favorite = cafeMenuItem(displayID: 1, name: "즐겨찾기", label: nil)
        let best = cafeMenuItem(displayID: 2, name: "베스트", label: "BEST")
        let new = cafeMenuItem(displayID: 3, name: "신메뉴", label: "NEW")
        let standard = cafeMenuItem(displayID: 4, name: "일반", label: nil)

        let sections = CafeMenuFilter.prioritySections(
            from: [standard, new, best, favorite],
            favoriteDisplayIDs: [favorite.displayID]
        )

        XCTAssertEqual(sections.map(\.group), [.favorite, .best, .new, .standard])
        XCTAssertEqual(sections.map { $0.items.map(\.displayID) }, [[1], [2], [3], [4]])
    }

    func testCafeMenuSearchAppliesFavoritePriorityPerShop() {
        let shop = Shop(id: 5, name: "카페", kind: .cafe, isOpen: true)
        let regular = cafeMenuItem(displayID: 20, name: "아메리카노 일반", label: nil)
        let favorite = cafeMenuItem(displayID: 21, name: "아메리카노 즐겨찾기", label: nil)

        let sections = CafeMenuFilter.sections(
            shops: [shop],
            menusByShop: [shop.id: [regular, favorite]],
            searchText: "아메리카노",
            favoriteDisplayIDsByShop: [shop.id: [favorite.displayID]]
        )

        XCTAssertEqual(sections.first?.items.map(\.displayID), [21, 20])
    }

    func testDiningMenuFilterRemovesEmptyOperationShells() {
        let emptyCourse = DiningCourse(
            name: "코스",
            price: 0,
            menus: [],
            isSoldOut: false,
            congestion: nil,
            origin: ""
        )
        let blankMeal = DiningMenuItem(
            name: "   ",
            calorie: nil,
            nutrition: "",
            information: "",
            imageURL: nil,
            isSoldOut: false
        )
        let blankCourse = DiningCourse(
            name: "코스",
            price: 0,
            menus: [blankMeal],
            isSoldOut: false,
            congestion: nil,
            origin: ""
        )
        let periods = [
            DiningPeriod(time: "조식", startTime: "08:00", endTime: "09:00", courses: []),
            DiningPeriod(time: "중식", startTime: "11:30", endTime: "13:30", courses: [emptyCourse, blankCourse]),
        ]

        XCTAssertTrue(DiningMenuFilter.periodsWithMeals(periods).isEmpty)
    }

    func testDiningMenuDetailContextIncludesCourseAvailabilityAndServingTime() {
        let meal = DiningMenuItem(
            name: "계란말이",
            calorie: 180,
            nutrition: "단백질 12g",
            information: "계란말이, 김치, 멸치볶음",
            imageURL: nil,
            isSoldOut: false
        )
        let context = DiningMenuDetailContext(
            meal: meal,
            sideDishSummary: "계란말이, 김치, 멸치볶음",
            courseName: "한식 코스",
            coursePrice: 7_000,
            courseIsSoldOut: true,
            congestion: "NORMAL",
            origin: "쌀 국내산",
            periodName: "중식",
            startTime: "11:30",
            endTime: "13:30",
            date: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(context.isSoldOut)
        XCTAssertEqual(context.servingTime, "11:30–13:30")
        XCTAssertEqual(context.meal.nutrition, "단백질 12g")
        XCTAssertEqual(context.origin, "쌀 국내산")
    }

    func testOrderDateFormattingAcceptsServerVariants() {
        XCTAssertNotNil(AppFormat.orderDate("2026-07-18T04:20:00.123Z"))
        XCTAssertNotNil(AppFormat.orderDate("2026-07-18 13:20:00"))
        XCTAssertEqual(AppFormat.orderTime("2026-07-18 13:20:00"), "오후 1:20")
    }

    func testOrderStatusMapperFindsNestedPayload() {
        let raw: JSONValue = .object([
            "content": .object([
                "order": .object([
                    "orderId": .int(314),
                    "orderNo": .string("A-0314"),
                    "orderStatus": .string("WAITING_FOR_PICKUP"),
                ]),
            ]),
        ])

        let result = EligaMapper.orderStatus(raw, fallbackOrderID: 1)

        XCTAssertEqual(result.orderID, 314)
        XCTAssertEqual(result.orderNumber, "A-0314")
        XCTAssertEqual(result.status, "WAITING_FOR_PICKUP")
    }

    func testOrderActivityPhaseMapsTerminalStates() {
        XCTAssertEqual(OrderActivityPhase(statusCode: "ORDER_RECEPTION"), .submitted)
        XCTAssertEqual(OrderActivityPhase(statusCode: "WAITING_FOR_PICKUP"), .ready)
        XCTAssertEqual(OrderActivityPhase(statusCode: "PICKUP_COMPLETE"), .completed)
        XCTAssertEqual(OrderActivityPhase(statusCode: "ORDER_CANCELLED"), .cancelled)
        XCTAssertTrue(OrderActivityPhase(statusCode: "ORDER_COMPLETE").isTerminal)
        XCTAssertFalse(OrderActivityPhase(statusCode: "PREPARING").isTerminal)
    }

    func testRemotePushPayloadSupportsNestedOrderValues() {
        let values = PushNotificationCoordinator.orderValues(from: [
            "order": [
                "id": "91",
                "orderNo": "B-91",
                "status": "WAITING_FOR_PICKUP",
            ],
        ])

        XCTAssertEqual(values.orderID, 91)
        XCTAssertEqual(values.orderNumber, "B-91")
        XCTAssertEqual(values.status, "WAITING_FOR_PICKUP")
    }

    func testOrderMonitoringStoragePersistsAndRemovesTrackedOrder() throws {
        let suiteName = "com.leeari95.NewEligaOrder.monitoring-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storage = OrderMonitoringStorage(defaults: defaults)
        let order = MonitoredOrder(
            orderID: 314,
            orderNumber: "A-0314",
            shopName: "엘리가 카페",
            phase: .submitted,
            startedAt: .now
        )

        storage.track(order)

        XCTAssertEqual(storage.orders, [order])
        XCTAssertTrue(storage.hasActiveOrders)

        storage.remove(orderID: order.orderID)

        XCTAssertTrue(storage.orders.isEmpty)
        XCTAssertFalse(storage.hasActiveOrders)
    }

    func testQuickOrderRecoveryJournalPersistsBeforeDestructiveIsolation() throws {
        let suiteName = "com.leeari95.NewEligaOrder.quick-order-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let journalDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quick-order-tests-\(UUID().uuidString)", isDirectory: true)
        let journalURL = journalDirectory.appendingPathComponent("recovery.json")
        defer { try? FileManager.default.removeItem(at: journalDirectory) }
        let preferences = PreferencesStore(defaults: defaults, quickOrderJournalURL: journalURL)
        let session = QuickOrderSession(
            id: UUID(),
            accountID: "tester@example.com",
            shopID: 5,
            goodsID: 101,
            quantity: 2,
            options: [SelectedOption(optionID: 7, menuIDs: [9, 8])],
            stashedLines: [
                CartRestoreLine(goodsID: 202, quantity: 3, options: [])
            ],
            phase: .stashed
        )

        try preferences.saveQuickOrderSession(session)

        defaults.removeObject(forKey: "eliga.quickOrder.recovery")
        let restored = try XCTUnwrap(
            PreferencesStore(defaults: defaults, quickOrderJournalURL: journalURL).quickOrderSession
        )
        XCTAssertEqual(restored.id, session.id)
        XCTAssertEqual(restored.accountID, session.accountID)
        XCTAssertEqual(restored.stashedLines, session.stashedLines)
        XCTAssertEqual(restored.phase, .stashed)

        try preferences.saveQuickOrderSession(nil)
        XCTAssertNil(preferences.quickOrderSession)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))
    }

    func testOrderMonitoringStoragePrunesExpiredOrders() throws {
        let suiteName = "com.leeari95.NewEligaOrder.monitoring-expiry-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storage = OrderMonitoringStorage(defaults: defaults)
        storage.track(
            MonitoredOrder(
                orderID: 99,
                orderNumber: "99",
                shopName: "카페",
                phase: .preparing,
                startedAt: Date.now.addingTimeInterval(-OrderMonitoringPolicy.maximumLifetime - 1)
            )
        )

        storage.removeExpired()

        XCTAssertTrue(storage.orders.isEmpty)
    }

    func testOrderMonitoringNotificationCopyMatchesReadyState() {
        XCTAssertEqual(
            OrderMonitoringPolicy.notificationTitle(for: .ready),
            "픽업할 준비가 됐어요"
        )
        XCTAssertEqual(
            OrderMonitoringPolicy.notificationBody(shopName: "1층 카페", orderNumber: "A-0314"),
            "1층 카페 · 주문 A-0314"
        )
    }

    private func cafeMenuItem(
        displayID: Int,
        name: String,
        label: String?
    ) -> CafeMenuItem {
        CafeMenuItem(
            displayID: displayID,
            goodsID: displayID,
            name: name,
            categoryID: 1,
            category: "음료",
            price: 3_000,
            isSoldOut: false,
            description: nil,
            calorie: nil,
            nutrition: nil,
            label: label,
            displayName: name,
            thumbnailURL: nil
        )
    }

    private func dynamicDiningInput() -> DiningDynamicUIInput {
        DiningDynamicUIInput(
            menuName: "제육볶음",
            information: """
            [원산지]
            제육볶음
            쌀밥
            된장국
            배추김치
            콩나물무침
            [알레르기 주의]
            대두 포함
            """,
            sideDishSummary: "쌀밥, 된장국, 배추김치, 콩나물무침",
            calorie: 650,
            nutrition: "단백질 27g, 나트륨 1200mg",
            origin: "돼지고기 국내산",
            courseName: "한식",
            coursePrice: 7_000,
            periodName: "중식",
            servingTime: "11:30–13:30",
            congestion: "보통",
            isSoldOut: false
        )
    }
}

private actor FoundationModelRequestProbe {
    private(set) var maximumConcurrentRequests = 0
    private var activeRequests = 0

    func begin(_ id: Int) {
        _ = id
        activeRequests += 1
        maximumConcurrentRequests = max(maximumConcurrentRequests, activeRequests)
    }

    func end(_ id: Int) {
        _ = id
        activeRequests -= 1
    }
}

private actor FoundationModelCancellationProbe {
    private(set) var result: Bool?
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func markStarted() {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func finish(inferenceWasCancelled: Bool) {
        result = inferenceWasCancelled
    }
}

private actor FoundationModelQueueGate {
    private var blocked = false
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func blockUntilReleased() async {
        blocked = true
        blockedWaiters.forEach { $0.resume() }
        blockedWaiters.removeAll()
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilBlocked() async {
        if blocked { return }
        await withCheckedContinuation { blockedWaiters.append($0) }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor FoundationModelCallCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private actor FoundationModelEnqueueProbe {
    private var count = 0
    private var waiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func markEnqueued() {
        count += 1
        let ready = waiters.filter { count >= $0.target }
        waiters.removeAll { count >= $0.target }
        ready.forEach { $0.continuation.resume() }
    }

    func wait(for target: Int) async {
        if count >= target { return }
        await withCheckedContinuation { waiters.append((target, $0)) }
    }
}
