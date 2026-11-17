#if os(iOS)
import XCTest

/// Every iPhone screen, sheet and state on fixture data (`-UITestFixtures`,
/// no backend), for review without a device: CI uploads them as the
/// `ios-screenshots` artifact. Layout is checked by LayoutTests; this only
/// captures. Each test launches fresh, so one screen never depends on
/// another, and captures even when a step fails (the failure is reported
/// next to the image).
final class PhoneScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    // MARK: - Helpers

    private func launch(plan: String = "free", localHour: Int = 10, language: String = "en",
                        dark: Bool = false, onboardingDone: Bool = true,
                        extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        let locales = ["en": "en_US", "nl": "nl_NL", "de": "de_DE", "es": "es_ES"]
        app.launchArguments = [
            "-UITestFixtures",
            "-UITestPlan", plan,
            "-UITestLocalHour", String(localHour),
            "-onboardingDone", onboardingDone ? "YES" : "NO",
            "-AppleLanguages", "(\(language))", "-AppleLocale", locales[language] ?? "en_US",
            "-UITestAppearance", dark ? "dark" : "light",
        ] + extra
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

    /// Taps `element` (scrolling to it first); reports instead of failing hard.
    @discardableResult
    private func tap(_ element: XCUIElement, _ what: String, in app: XCUIApplication,
                     timeout: TimeInterval = 5) -> Bool {
        if !element.waitForExistence(timeout: timeout) || !element.isHittable {
            Layout.scrollTo(element, in: app)
        }
        guard element.exists, element.isHittable else {
            XCTFail("could not reach \(what)")
            return false
        }
        element.tap()
        settle(1.5)
        return true
    }

    private func button(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func button(_ app: XCUIApplication, beginningWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func id(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func openTab(_ app: XCUIApplication, _ label: String) {
        tap(app.tabBars.buttons[label], "\(label) tab", in: app)
    }

    /// Spot Detail of the first "More nearby" row (the decision card opens
    /// the spot at its window hour; a plain row is the common path).
    private func openSpotDetail(_ app: XCUIApplication) {
        waitForResults(app, "detail")
        tap(Layout.firstPlainRow(app), "first nearby row", in: app)
        if !app.buttons["spotAction.directions"].waitForExistence(timeout: 10) {
            XCTFail("Spot Detail did not open")
        }
        settle(1.5)
    }

    // MARK: - Onboarding

    func test01Onboarding() {
        let app = launch(onboardingDone: false)
        let next = button(app, "Continue")
        if !next.waitForExistence(timeout: 10) { XCTFail("onboarding not shown") }
        settle(1)
        capture("01-onboarding-welcome")
        if tap(next, "Continue", in: app) {
            capture("02-onboarding-where")
            if tap(button(app, "Choose a City"), "Choose a City", in: app) {
                capture("03-onboarding-city-list")
                if tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Amsterdam")).firstMatch,
                       "Amsterdam row", in: app) {
                    capture("04-onboarding-good-day-tips")
                }
            }
        }
        app.terminate()
    }

    // MARK: - Best Now

    func test02BestNow() {
        let app = launch()
        waitForResults(app, "best now")
        capture("05-best-now")
        app.swipeUp(velocity: .slow)
        settle(1)
        capture("06-best-now-scrolled")
        app.swipeUp(velocity: .slow)
        settle(1)
        capture("07-best-now-bottom")
        app.terminate()
    }

    /// Responses held back 30 s: the skeleton rows while Best Now loads.
    func test03Loading() {
        let app = launch(extra: ["-UITestDelay", "30"])
        settle(4)
        capture("08-best-now-loading")
        app.terminate()
    }

    /// Every request fails as "not connected to the internet".
    func test04Offline() {
        let app = launch(extra: ["-UITestOffline", "YES"])
        settle(8)
        capture("09-best-now-offline")
        app.terminate()
    }

    func test05Night() {
        let app = launch(localHour: 2)
        waitForResults(app, "night")
        capture("10-best-now-night")
        app.terminate()
    }

    func test06Dark() {
        let app = launch(dark: true)
        waitForResults(app, "dark")
        capture("11-best-now-dark")
        openSpotDetail(app)
        capture("12-spot-detail-dark")
        app.terminate()
    }

    func test07German() {
        let app = launch(language: "de")
        waitForResults(app, "de")
        capture("13-best-now-de")
        openSpotDetail(app)
        capture("14-spot-detail-de")
        app.terminate()
    }

    // MARK: - Place, time, filters, getaways

    func test08PlaceMenuAndCityPicker() {
        let app = launch()
        waitForResults(app, "place")
        if tap(button(app, "Amsterdam"), "place menu", in: app) {
            capture("15-place-menu")
            if tap(button(app, "Choose a City…"), "Choose a City…", in: app) {
                capture("16-city-picker")
            }
        }
        app.terminate()
    }

    func test09Getaways() {
        let app = launch()
        waitForResults(app, "getaways")
        if tap(button(app, "Amsterdam"), "place menu", in: app),
           tap(button(app, "Where's Nice This Weekend?"), "Where's Nice This Weekend?", in: app) {
            settle(1.5)
            capture("17-getaways")
        }
        app.terminate()
    }

    func test10WhenMenuAndTimePicker() {
        let app = launch()
        waitForResults(app, "when")
        // The menu's label reads "Time: Now".
        if tap(button(app, beginningWith: "Time"), "When menu", in: app) {
            capture("18-when-menu")
            if tap(button(app, "Choose a Time…"), "Choose a Time…", in: app) {
                capture("19-time-picker")
            }
        }
        app.terminate()
    }

    func test11Filters() {
        let app = launch()
        waitForResults(app, "filters")
        if tap(button(app, "Filters"), "Filters", in: app) {
            capture("20-filters")
        }
        app.terminate()
    }

    // MARK: - Spot Detail and its sheets

    func test12SpotDetail() {
        let app = launch()
        openSpotDetail(app)
        capture("21-spot-detail")
        app.swipeUp(velocity: .slow)
        settle(1)
        capture("22-spot-detail-scrolled")
        app.swipeUp(velocity: .slow)
        settle(1)
        capture("23-spot-detail-bottom")
        app.terminate()
    }

    func test13ScoreBreakdown() {
        let app = launch()
        openSpotDetail(app)
        if tap(button(app, beginningWith: "Why"), "Why NN?", in: app) {
            capture("24-score-breakdown")
        }
        app.terminate()
    }

    func test14AlertEditor() {
        let app = launch()
        openSpotDetail(app)
        if tap(app.buttons["spotAction.alert"], "Alert", in: app) {
            capture("25-alert-editor")
        }
        app.terminate()
    }

    func test15Report() {
        let app = launch()
        openSpotDetail(app)
        if tap(button(app, "Is this spot still here?"), "Is this spot still here?", in: app) {
            capture("26-report")
        }
        app.terminate()
    }

    // MARK: - Plans, Saved

    /// Plan It on the decision card, then the plan in Saved and its sheet.
    func test16Plans() {
        let app = launch()
        waitForResults(app, "plans")
        if tap(id(app, "planItButton"), "Plan It", in: app) {
            capture("27-planned")
        }
        openTab(app, "Saved")
        capture("28-saved-with-plan")
        if tap(id(app, "picnicPlanRow"), "plan row", in: app) {
            capture("29-plan-sheet")
        }
        app.terminate()
    }

    func test17SavedFree() {
        let app = launch()
        waitForResults(app, "saved free")
        openTab(app, "Saved")
        capture("30-saved-free")
        app.terminate()
    }

    func test18SavedPlus() {
        let app = launch(plan: "plus")
        waitForResults(app, "saved plus")
        openTab(app, "Saved")
        capture("31-saved-plus")
        app.swipeUp(velocity: .slow)
        settle(1)
        capture("32-saved-plus-scrolled")
        app.terminate()
    }

    // MARK: - Map

    func test19Map() {
        let app = launch()
        waitForResults(app, "map")
        openTab(app, "Map")
        settle(2)   // tiles
        capture("33-map")
        let pin = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Vondelpark")).firstMatch
        if tap(pin, "Vondelpark pin", in: app) {
            settle(1)
            capture("34-map-spot-sheet")
        }
        app.terminate()
    }

    // MARK: - Settings, paywall

    func test20Settings() {
        let app = launch()
        waitForResults(app, "settings")
        openTab(app, "Settings")
        capture("35-settings")
        app.swipeUp(velocity: .slow)
        settle(1)
        capture("36-settings-bottom")
        if tap(button(app, "Delete My Data"), "Delete My Data", in: app) {
            capture("37-delete-data-confirm")
        }
        app.terminate()
    }

    func test21SettingsPlus() {
        let app = launch(plan: "plus")
        waitForResults(app, "settings plus")
        openTab(app, "Settings")
        capture("38-settings-plus")
        app.terminate()
    }

    func test22Paywall() {
        let app = launch()
        waitForResults(app, "paywall")
        if tap(button(app, "See more picks with Plus"), "See more picks with Plus", in: app) {
            settle(1)
            capture("39-paywall")
            app.swipeUp(velocity: .slow)
            settle(1)
            capture("40-paywall-bottom")
            // Dismissing may ask why (PaywallSurvey).
            app.swipeDown(velocity: .fast)
            settle(2)
            capture("41-paywall-dismissed")
        }
        app.terminate()
    }
}
#endif
