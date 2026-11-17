#if os(iOS)
import XCTest

/// Screenshots of the main iPhone screens on fixture data (`-UITestFixtures`,
/// no backend), for review without a device: CI uploads them as the
/// `ios-screenshots` artifact. Layout is checked by LayoutTests; this only
/// captures. Each screen is captured even when its wait fails (the failure
/// is reported next to the image).
final class PhoneScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func launch(plan: String = "free", localHour: Int = 10, language: String = "en",
                        dark: Bool = false, onboardingDone: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        let locales = ["en": "en_US", "nl": "nl_NL", "de": "de_DE", "es": "es_ES"]
        app.launchArguments = [
            "-UITestFixtures",
            "-UITestPlan", plan,
            "-UITestLocalHour", String(localHour),
            "-onboardingDone", onboardingDone ? "YES" : "NO",
            "-AppleLanguages", "(\(language))", "-AppleLocale", locales[language] ?? "en_US",
            "-UITestAppearance", dark ? "dark" : "light",
        ]
        app.launch()
        return app
    }

    @discardableResult
    private func waitForResults(_ app: XCUIApplication, _ context: String) -> XCUIElement {
        let top = app.descendants(matching: .any).matching(identifier: "spotRow.top").firstMatch
        if !top.waitForExistence(timeout: 15) {
            XCTFail("[\(context)] Best Now never loaded")
        }
        settle(1.5)
        return top
    }

    private func settle(_ seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: seconds)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openTab(_ app: XCUIApplication, _ label: String) {
        let tab = app.tabBars.buttons[label]
        if tab.waitForExistence(timeout: 5) { tab.tap() } else { XCTFail("no \(label) tab") }
        settle(1.5)
    }

    // MARK: - Screens

    func test01Onboarding() {
        let app = launch(onboardingDone: false)
        if !app.buttons["Continue"].waitForExistence(timeout: 10) { XCTFail("onboarding not shown") }
        settle(1)
        capture("01-onboarding")
        app.terminate()
    }

    func test02BestNow() {
        let app = launch()
        waitForResults(app, "best now")
        capture("02-best-now")
        app.swipeUp(velocity: .slow)
        settle(1)
        capture("03-best-now-scrolled")
        app.terminate()
    }

    func test04BestNowDark() {
        let app = launch(dark: true)
        waitForResults(app, "dark")
        capture("04-best-now-dark")
        app.terminate()
    }

    func test05Night() {
        let app = launch(localHour: 2)
        waitForResults(app, "night")
        capture("05-night-next-good-time")
        app.terminate()
    }

    func test06SpotDetail() {
        let app = launch()
        let top = waitForResults(app, "detail")
        if top.exists {
            top.tap()
            if !app.buttons["spotAction.directions"].waitForExistence(timeout: 10) {
                XCTFail("[detail] Spot Detail did not open")
            }
            settle(2)
        }
        capture("06-spot-detail")
        app.swipeUp(velocity: .slow)
        settle(1)
        capture("07-spot-detail-scrolled")
        app.terminate()
    }

    func test08Map() {
        let app = launch()
        waitForResults(app, "map")
        openTab(app, "Map")
        settle(2)   // tiles
        capture("08-map")
        app.terminate()
    }

    func test09SavedPlus() {
        let app = launch(plan: "plus")
        waitForResults(app, "saved")
        openTab(app, "Saved")
        capture("09-saved-plus")
        app.terminate()
    }

    func test10Settings() {
        let app = launch()
        waitForResults(app, "settings")
        openTab(app, "Settings")
        capture("10-settings")
        app.terminate()
    }

    func test11Paywall() {
        let app = launch()
        waitForResults(app, "paywall")
        let more = app.buttons["See more picks with Plus"]
        Layout.scrollTo(more, in: app)
        if more.exists && more.isHittable {
            more.tap()
            settle(2)
        } else {
            XCTFail("[paywall] no See more picks with Plus button")
        }
        capture("11-paywall")
        app.terminate()
    }

    func test12German() {
        let app = launch(language: "de")
        waitForResults(app, "de")
        capture("12-best-now-de")
        app.terminate()
    }
}
#endif
