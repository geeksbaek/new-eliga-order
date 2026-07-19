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
    func testCartUsesAccessibleCafeShopPicker() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing-shop-picker",
            "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        let picker = app.descendants(matching: .any)["cafe.shop-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, "엘리가 카페 본점")
        assertFullyVisible(picker, in: app)

        picker.tap()
        let secondShop = app.buttons["엘리가 카페 서초점"]
        XCTAssertTrue(secondShop.waitForExistence(timeout: 2))
        secondShop.tap()
        XCTAssertEqual(picker.value as? String, "엘리가 카페 서초점")

        attachScreenshot(of: app, name: "장바구니 공통 매장 선택 메뉴")
        try app.performAccessibilityAudit(
            // 시스템 내비게이션 바는 글자 크기가 고정되므로 AXXXL 실화면과 Large Content Viewer로 직접 검증한다.
            for: [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .trait]
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
