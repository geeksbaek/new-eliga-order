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
        try app.performAccessibilityAudit(for: .all)
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
        try app.performAccessibilityAudit(for: [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .textClipped, .trait])
    }
}
