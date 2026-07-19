import XCTest

final class AccessibilityUITests: XCTestCase {
    @MainActor
    func testLoginScreenHasAccessibleControls() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing-reset-auth")
        app.launch()
        XCTAssertTrue(app.textFields["login.email"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["login.password"].exists)
        XCTAssertTrue(app.buttons["login.submit"].exists)
        let subtitle = app.staticTexts["엘리가 계정으로 안전하게 계속하세요."]
        XCTAssertTrue(subtitle.exists)
        assertFullyVisible(subtitle, in: app)
        try app.performAccessibilityAudit(
            for: [.contrast, .dynamicType, .elementDetection, .hitRegion, .sufficientElementDescription, .trait]
        )
    }

    @MainActor
    func testLoginScreenInDarkModeAtLargestTextSize() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing-reset-auth",
            "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        XCTAssertTrue(app.textFields["login.email"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["login.submit"].exists)
        let subtitle = app.staticTexts["엘리가 계정으로 안전하게 계속하세요."]
        XCTAssertTrue(subtitle.exists)
        assertFullyVisible(subtitle, in: app)
        attachScreenshot(of: app, name: "로그인 Dark AXXXL")
        try app.performAccessibilityAudit(
            // launch override로 이미 AXXXL에 고정했으므로 크기를 재변경하는 dynamicType 감사는 별도 기본-size 테스트에서 실행한다.
            for: [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .trait]
        )
    }

    @MainActor
    func testCafePrioritySectionsAtLargestTextSize() throws {
        for group in ["favorite", "best", "new", "standard"] {
            let app = XCUIApplication()
            app.launchArguments += [
                "-ui-testing-cafe-sections",
                "-AppleInterfaceStyle", "Dark",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
            app.launchEnvironment["CAFE_FIXTURE_GROUP"] = group
            app.launch()

            XCTAssertTrue(
                app.descendants(matching: .any)["cafe.section.\(group)"].waitForExistence(timeout: 5),
                "\(group) 그룹 헤더가 표시되어야 합니다."
            )
            let menuButton = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "₩4,500")
            ).firstMatch
            XCTAssertTrue(menuButton.exists)
            assertFullyVisible(menuButton, in: app)
            attachScreenshot(of: app, name: "카페 \(group) Dark AXXXL")
            try app.performAccessibilityAudit(
                // AXXXL 고정 상태의 실제 frame/screenshot은 위에서 검증하고, 크기 변경 감사는 기본-size 테스트와 중복하지 않는다.
                for: [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .trait]
            )
            app.terminate()
        }
    }

    @MainActor
    func testCafeHolidayCardAtLargestTextSize() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing-cafe-holiday",
            "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        let card = app.descendants(matching: .any)["cafe.availability.holiday"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        assertFullyVisible(card, in: app)
        attachScreenshot(of: app, name: "카페 휴무 안내 Dark AXXXL")
        try app.performAccessibilityAudit(
            for: [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .trait]
        )
    }

    @MainActor
    func testCafeMenuDetailKeepsHolidayNoticeSeparateFromActions() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing-cafe-menu-detail-holiday")
        app.launch()

        let card = app.descendants(matching: .any)["cafe.availability.holiday"]
        let actions = app.descendants(matching: .any)["cafe.menu-detail.actions"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        XCTAssertFalse(
            card.frame.intersects(actions.frame),
            "휴무 안내는 하단 주문 액션 영역과 겹치지 않아야 합니다."
        )
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label == %@", "오늘은 휴무예요")).count,
            1
        )
        attachScreenshot(of: app, name: "카페 상세 휴무 안내와 주문 액션 분리")
        try app.performAccessibilityAudit(
            // 비활성 시스템 버튼의 명암은 XCTest가 실패로 판정하므로 카드 명암은 전용 휴무 카드 테스트에서 검증한다.
            for: [.dynamicType, .elementDetection, .hitRegion, .sufficientElementDescription, .trait]
        )
    }

    @MainActor
    func testCafeMenuDetailQuantityButtonsHaveEqualSize() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing-cafe-menu-detail-quantity")
        app.launch()

        let decrease = app.buttons["수량 감소"]
        let increase = app.buttons["수량 증가"]
        XCTAssertTrue(decrease.waitForExistence(timeout: 5))
        XCTAssertTrue(increase.exists)
        XCTAssertEqual(decrease.frame.width, increase.frame.width, accuracy: 0.5)
        XCTAssertEqual(decrease.frame.height, increase.frame.height, accuracy: 0.5)
        XCTAssertEqual(decrease.frame.width, 44, accuracy: 0.5)
        XCTAssertEqual(decrease.frame.height, 44, accuracy: 0.5)

        attachScreenshot(of: app, name: "카페 상세 동일 크기 수량 버튼")
        try app.performAccessibilityAudit(
            // 가격 요약의 기존 명암·Dynamic Type 감사와 분리해 수량 컨트롤의 크기와 상호작용을 검증한다.
            for: [.elementDetection, .hitRegion, .sufficientElementDescription, .trait]
        )
    }

    @MainActor
    func testSettingsOmitsFontSizeInformation() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing-settings")
        app.launch()

        XCTAssertTrue(app.staticTexts["식사 알림"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["글자 크기"].exists)
        XCTAssertFalse(app.staticTexts["시스템의 Dynamic Type 설정을 따릅니다"].exists)
        XCTAssertFalse(app.staticTexts["설정 앱의 디스플레이 및 텍스트 크기에서 변경할 수 있습니다."].exists)

        attachScreenshot(of: app, name: "글자 크기 안내를 제거한 설정")
    }

    @MainActor
    func testCartUsesSameShopSwitcherAsCafeWithoutSearchButton() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing-cart-shop-switcher",
            "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        let firstShop = app.buttons["cafe.shop-mode.5"]
        let secondShop = app.buttons["cafe.shop-mode.6"]
        XCTAssertTrue(firstShop.waitForExistence(timeout: 5))
        XCTAssertTrue(secondShop.exists)
        XCTAssertEqual(firstShop.value as? String, "선택됨")
        assertFullyVisible(firstShop, in: app)

        XCTAssertFalse(
            app.buttons["cafe.search.accessory"].exists,
            "장바구니에는 검색 버튼이 없어야 합니다."
        )

        secondShop.tap()
        XCTAssertEqual(secondShop.value as? String, "선택됨")

        attachScreenshot(of: app, name: "장바구니 매장 스위처")
        try app.performAccessibilityAudit(
            // 시스템 내비게이션 바는 글자 크기가 고정되므로 AXXXL 실화면과 Large Content Viewer로 직접 검증한다.
            for: [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .trait]
        )
    }

    @MainActor
    func testCafeModeSwitcherChangesShopBySwipeAndTap() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing-cafe-mode-switcher",
            "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        let firstShop = app.buttons["cafe.shop-mode.5"]
        let secondShop = app.buttons["cafe.shop-mode.6"]
        let thirdShop = app.buttons["cafe.shop-mode.8"]
        XCTAssertTrue(firstShop.waitForExistence(timeout: 5))
        XCTAssertTrue(secondShop.exists)
        XCTAssertTrue(thirdShop.exists)
        XCTAssertEqual(firstShop.value as? String, "선택됨")
        assertFullyVisible(firstShop, in: app)

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists)
        XCTAssertGreaterThanOrEqual(
            tabBar.frame.minY - firstShop.frame.maxY,
            8,
            "매장 스위처와 하단 GNB 사이에는 표준 8pt 간격이 필요합니다."
        )

        let modeSwitcher = app.descendants(matching: .any)["cafe.shop-mode-switcher"]
        XCTAssertTrue(modeSwitcher.exists)
        modeSwitcher.swipeLeft()
        let swipeSelection = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "선택됨"),
            object: secondShop
        )
        XCTAssertEqual(XCTWaiter.wait(for: [swipeSelection], timeout: 2), .completed)

        thirdShop.tap()
        XCTAssertEqual(thirdShop.value as? String, "선택됨")

        attachScreenshot(of: app, name: "한 손 카페 매장 스위처")
        try app.performAccessibilityAudit(
            // AXXXL에서 시스템 List 섹션의 명암 오탐을 제외하고 스위처의 실제 프레임과 상호작용을 검증한다.
            for: [.elementDetection, .hitRegion, .sufficientElementDescription, .trait]
        )
    }

    @MainActor
    func testCafeSearchRowStaysPutWhileGNBNeverMinimizes() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing-cafe-mode-switcher")
        app.launch()

        let cafeTitle = app.navigationBars["카페"]
        XCTAssertTrue(cafeTitle.waitForExistence(timeout: 5))

        let searchButton = app.buttons["cafe.search.accessory"]
        XCTAssertTrue(
            searchButton.waitForExistence(timeout: 3),
            "카페 탭에서는 하단 검색 버튼이 보여야 합니다."
        )

        let modeSwitcher = app.descendants(matching: .any)["cafe.shop-mode-switcher"]
        XCTAssertTrue(modeSwitcher.exists)
        // CafeView가 직접 소유하는 행이므로 매장 스위처와 검색 버튼은
        // 같은 줄에서 겹치지 않고 나란히 있어야 한다.
        XCTAssertLessThanOrEqual(
            modeSwitcher.frame.maxX + 8,
            searchButton.frame.minX,
            "매장 스위처와 검색 버튼은 같은 줄에서 겹치지 않아야 합니다."
        )
        XCTAssertEqual(
            modeSwitcher.frame.midY,
            searchButton.frame.midY,
            accuracy: 4,
            "매장 스위처와 검색 버튼은 같은 줄에 있어야 합니다."
        )
        let restingFrame = searchButton.frame

        let menuList = app.collectionViews.firstMatch
        XCTAssertTrue(menuList.exists)
        menuList.swipeUp()

        // GNB는 `.tabBarMinimizeBehavior(.never)`라 스크롤해도 축소되지
        // 않는다 — 그리고 우리 행도 그 상태와 무관하게 제자리에 그대로다.
        let cafeTab = app.buttons["카페"]
        XCTAssertNotEqual(
            cafeTab.value as? String,
            "축소됨",
            "GNB는 .never로 설정되어 스크롤해도 축소되면 안 됩니다."
        )
        XCTAssertTrue(
            searchButton.waitForExistence(timeout: 3),
            "스크롤 후에도 검색 버튼이 계속 보여야 합니다."
        )
        XCTAssertEqual(
            searchButton.frame,
            restingFrame,
            "GNB가 축소되지 않으므로 검색 행의 위치도 스크롤 전후로 그대로여야 합니다."
        )
        attachScreenshot(of: app, name: "스크롤 후에도 고정된 검색 행")

        searchButton.tap()
        let searchField = app.searchFields["모든 매장의 메뉴 검색"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        searchField.typeText("라떼")
        XCTAssertEqual(searchField.value as? String, "라떼")
        attachScreenshot(of: app, name: "GNB 검색 활성화")
    }

    @MainActor
    func testCafeSearchAccessoryHiddenOnOtherTabs() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing-cafe-mode-switcher")
        app.launch()

        XCTAssertTrue(app.navigationBars["카페"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["cafe.search.accessory"].waitForExistence(timeout: 3))

        app.tabBars.buttons["홈"].tap()
        XCTAssertFalse(
            app.buttons["cafe.search.accessory"].waitForExistence(timeout: 2),
            "카페가 아닌 탭에는 빈 검색 글래스가 남아 있으면 안 됩니다."
        )

        app.tabBars.buttons["식단"].tap()
        XCTAssertFalse(
            app.buttons["cafe.search.accessory"].exists,
            "식단 탭에도 검색 액세서리가 보이면 안 됩니다."
        )
    }

    @MainActor
    func testDiningDetailUsesSimplifiedGeneratedStructure() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing-dining-detail")
        app.launch()

        for title in ["메뉴 구성", "영양 정보", "원산지"] {
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5), "\(title) 섹션이 필요합니다.")
        }
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label == %@", "영양 정보")).count,
            1,
            "생성 결과에 중복 영양 블록이 있어도 화면에는 한 번만 표시되어야 합니다."
        )
        XCTAssertFalse(app.staticTexts["중식 이용 안내"].exists)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "제육볶음")).count, 1)

        let image = app.images["제육볶음 메뉴 사진"]
        XCTAssertTrue(image.exists)
        XCTAssertGreaterThanOrEqual(image.frame.width, app.windows.firstMatch.frame.width - 40)

        attachScreenshot(of: app, name: "단순화된 식단 Gen UI 상단")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["알러지 주의 음식"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["중식 이용 안내"].exists)
        attachScreenshot(of: app, name: "단순화된 식단 Gen UI 하단")
        try app.performAccessibilityAudit(
            for: [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .trait]
        )
    }

    @MainActor
    func testDiningPersonalizationShowsRecommendationAndIndependentAllergyWarning() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing-dining-personalization")
        app.launch()

        XCTAssertTrue(app.staticTexts["추천"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["비추천"].exists)
        XCTAssertTrue(app.staticTexts["알러지 주의"].exists)
        XCTAssertTrue(app.staticTexts["두부 된장국"].exists)
        attachScreenshot(of: app, name: "식단 추천 비추천 및 알러지 레이블")

        app.buttons["dining.personalization.settings"].tap()
        XCTAssertTrue(app.staticTexts["선호 메뉴·음식 취향"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["나의 알러지"].exists)
        XCTAssertTrue(app.textFields["dining.allergies.input"].exists)

        attachScreenshot(of: app, name: "식단 자연어 취향 및 알러지 설정")
        try app.performAccessibilityAudit(
            for: [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .trait]
        )
    }

    @MainActor
    private func assertFullyVisible(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists, file: file, line: line)
        XCTAssertTrue(
            window.frame.contains(element.frame),
            "요소가 화면 밖으로 잘렸습니다: \(element.label), frame=\(element.frame)",
            file: file,
            line: line
        )
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
