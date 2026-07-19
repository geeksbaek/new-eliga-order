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
