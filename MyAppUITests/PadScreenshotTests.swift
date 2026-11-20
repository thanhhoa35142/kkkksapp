#if os(iOS)
import XCTest

/// iPad screenshots for the App Store (13-inch, landscape: 2752 × 2064) on
/// fixture data (`-UITestFixtures`, no backend). CI runs them on an iPad
/// Pro 13-inch simulator after group b's tests and uploads the
/// `ipad-screenshots` artifact. Landscape so the split view shows sidebar,
/// map and inspector together (portrait hides the sidebar). Group b's iPhone
/// run skips them (`-skip-testing`).
final class PadScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    // MARK: - Helpers

    private func launch(plan: String = "free", dark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestFixtures",
            "-UITestPlan", plan,
            "-UITestLocalHour", "10",
            "-onboardingDone", "YES",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-UITestAppearance", dark ? "dark" : "light",
        ]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        return app
    }

    @discardableResult
    private func waitForResults(_ app: XCUIApplication, _ context: String) -> XCUIElement {
        let top = id(app, "spotRow.top")
        if !top.waitForExistence(timeout: 20) {
            XCTFail("[\(context)] Best Now never loaded")
        }
        settle(2)
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

    private func id(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func button(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Scrolls the sidebar (not the map) until `element` can be tapped.
    private func scrollSidebar(to element: XCUIElement, in app: XCUIApplication) {
        let list = app.collectionViews.firstMatch
        var tries = 0
        while list.exists && !(element.exists && element.isHittable) && tries < 8 {
            list.swipeUp(velocity: .slow)
            tries += 1
        }
    }

    // MARK: - Screens

    func test01ExploreLight() {
        let app = launch()
        waitForResults(app, "explore")
        capture("01-explore-light")
        app.terminate()
    }

    func test02SpotDetail() {
        spotDetail(dark: false, name: "02-spot-detail")
    }

    func test03SpotDetailDark() {
        spotDetail(dark: true, name: "03-spot-detail-dark")
    }

    private func spotDetail(dark: Bool, name: String) {
        let app = launch(dark: dark)
        let top = waitForResults(app, "detail")
        if top.exists {
            top.tap()
            // The inspector's own controls: `weather.strip` is also in the
            // sidebar, so waiting on it captured before the inspector loaded.
            if !id(app, "spotAction.directions").waitForExistence(timeout: 10) {
                XCTFail("[detail] spot detail did not open in the inspector")
            }
            settle(2.5)
        }
        capture(name)
        app.terminate()
    }

    func test04ExplorePlus() {
        let app = launch(plan: "plus")
        waitForResults(app, "plus")
        capture("04-explore-plus")
        app.terminate()
    }

    func test05WeekPlan() {
        let app = launch(plan: "plus")
        waitForResults(app, "week plan")
        let row = id(app, "planRow")
        if !row.waitForExistence(timeout: 10) {
            XCTFail("[week plan] no week plan rows for the saved spots")
        }
        scrollSidebar(to: row, in: app)
        settle(1)
        capture("05-week-plan")
        app.terminate()
    }

    /// Plan It on the decision card, then the plan sheet from the Plans row.
    func test06Plan() {
        let app = launch()
        waitForResults(app, "plan")
        let planIt = id(app, "planItButton")
        guard planIt.waitForExistence(timeout: 5) else {
            XCTFail("[plan] no Plan It button on the decision card")
            capture("06-plan-sheet")
            app.terminate()
            return
        }
        planIt.tap()
        let row = id(app, "picnicPlanRow")
        if !row.waitForExistence(timeout: 5) {
            XCTFail("[plan] Plan It added no row to the Plans section")
        }
        scrollSidebar(to: row, in: app)
        if row.exists && row.isHittable {
            row.tap()
            settle(1.5)
        }
        capture("06-plan-sheet")
        app.terminate()
    }

    /// The paywall with the launch prices (fixture mode has no StoreKit).
    func test07Paywall() {
        let app = launch()
        waitForResults(app, "paywall")
        let more = button(app, "See more picks with Plus")
        if !more.waitForExistence(timeout: 5) { XCTFail("[paywall] no See more picks with Plus button") }
        scrollSidebar(to: more, in: app)
        if more.exists && more.isHittable {
            more.tap()
            // The price sits inside the row's button, so match any element.
            let price = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", "$29.99")).firstMatch
            if !price.waitForExistence(timeout: 5) {
                XCTFail("[paywall] no fixture price on the paywall")
            }
            settle(1.5)
        }
        capture("07-paywall")
        app.terminate()
    }

    func test08Settings() {
        let app = launch()
        waitForResults(app, "settings")
        let settings = app.buttons["Settings"].firstMatch
        if settings.waitForExistence(timeout: 5) {
            settings.tap()
            settle(1.5)
        } else {
            XCTFail("[settings] no Settings button in the toolbar")
        }
        capture("08-settings")
        app.terminate()
    }
}
#endif
