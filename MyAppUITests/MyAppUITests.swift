import XCTest

final class MyAppUITests: XCTestCase {

    /// Smoke test on fixture data: the app opens straight to the tabs.
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFixtures", "-onboardingDone", "YES"]
        app.launch()

        #if os(iOS)
        XCTAssertTrue(app.tabBars.buttons["Best Now"].waitForExistence(timeout: 10))
        #else
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        #endif
    }

    /// First launch shows onboarding, not a paywall or a permission prompt.
    func testFirstLaunchShowsOnboarding() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFixtures", "-onboardingDone", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 10)
                      || app.buttons["Get Started"].waitForExistence(timeout: 2),
                      "onboarding's first button not found")
    }
}
