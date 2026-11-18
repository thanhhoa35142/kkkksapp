#if os(macOS)
import XCTest

/// Screenshots of the native Mac app on fixture data (`-UITestFixtures`, no
/// backend), for review without a Mac: CI exports the attachments and
/// uploads them as the `macos-screenshots` artifact.
///
/// Each screen is captured even when its wait fails (the failure is reported
/// next to the image), so a broken layout still produces a picture.
final class MacScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func launch(plan: String = "free", localHour: Int = 10, language: String = "en",
                        dark: Bool = false, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        let locales = ["en": "en_US", "nl": "nl_NL", "de": "de_DE", "es": "es_ES"]
        app.launchArguments = [
            "-UITestFixtures",
            "-UITestPlan", plan,
            "-UITestLocalHour", String(localHour),
            "-onboardingDone", "YES",
            "-AppleLanguages", "(\(language))", "-AppleLocale", locales[language] ?? "en_US",
            // Fixture mode applies it as the preferred color scheme; the
            // runner itself stays in light mode.
            "-UITestAppearance", dark ? "dark" : "light",
            // No window restoration: a fresh window at the scene's default
            // size on every launch (a restored "no windows" state opens none).
            "-NSQuitAlwaysKeepsWindows", "NO",
            "-ApplePersistenceIgnoreState", "YES",
        ] + extra
        app.launch()
        app.activate()
        ensureMainWindow(app)
        return app
    }

    /// A Mac launch must show the main window. If it does not, that is
    /// reported, and File › New Window (⌘N) opens one so the screens still
    /// get captured.
    private func ensureMainWindow(_ app: XCUIApplication) {
        let main = app.windows.matching(NSPredicate(format: "title != %@", "Settings")).firstMatch
        if main.waitForExistence(timeout: 8) { return }
        XCTFail("no main window after launch (windows: \(app.windows.count)); opening one with ⌘N")
        app.typeKey("n", modifierFlags: .command)
        if !main.waitForExistence(timeout: 8) {
            XCTFail("⌘N opened no window either")
            add(XCTAttachment(string: app.debugDescription))
        }
    }

    /// Waits for the Best Now answer (decision card or top pick), then a
    /// moment more for map tiles and the ring animation.
    @discardableResult
    private func waitForResults(_ app: XCUIApplication, _ context: String) -> XCUIElement {
        let top = app.descendants(matching: .any).matching(identifier: "spotRow.top").firstMatch
        if !top.waitForExistence(timeout: 20) {
            XCTFail("[\(context)] Best Now never loaded")
        }
        // A new window's sidebar can open scrolled past the answer.
        if top.exists && !top.isHittable { scrollIntoView(top, in: app) }
        settle(2)
        return top
    }

    private func settle(_ seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: seconds)
    }

    private func capture(_ app: XCUIApplication, _ name: String, window: XCUIElement? = nil) {
        let target = window ?? app.windows.firstMatch
        let shot = target.exists ? target.screenshot() : XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Screens

    func test01ExploreLight() {
        let app = launch()
        waitForResults(app, "explore")
        capture(app, "01-explore-light")
        app.terminate()
    }

    func test02SpotDetailInspector() {
        spotDetailInspector(dark: false, name: "02-spot-detail")
    }

    /// The website's Mac image in dark appearance.
    func test02bSpotDetailInspectorDark() {
        spotDetailInspector(dark: true, name: "02b-spot-detail-dark")
    }

    private func spotDetailInspector(dark: Bool, name: String) {
        let app = launch(dark: dark)
        let top = waitForResults(app, "detail")
        if top.exists {
            top.click()
            let strip = app.descendants(matching: .any).matching(identifier: "weather.strip").firstMatch
            if !strip.waitForExistence(timeout: 10) {
                XCTFail("[detail] spot detail did not open in the inspector")
            }
            settle(2)
        }
        capture(app, name)
        app.terminate()
    }

    func test03ExploreDark() {
        let app = launch(dark: true)
        waitForResults(app, "dark")
        capture(app, "03-explore-dark")
        app.terminate()
    }

    func test04Night() {
        let app = launch(localHour: 2)
        waitForResults(app, "night")
        let next = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Next good time")).firstMatch
        if !next.waitForExistence(timeout: 5) {
            XCTFail("[night] no Next good time card at 2 AM")
        }
        capture(app, "04-night-next-good-time")
        app.terminate()
    }

    func test05Plus() {
        let app = launch(plan: "plus")
        waitForResults(app, "plus")
        capture(app, "05-explore-plus")
        app.terminate()
    }

    func test06Settings() {
        let app = launch()
        waitForResults(app, "settings")
        app.typeKey(",", modifierFlags: .command)
        // The Settings scene opens as its own window.
        let predicate = NSPredicate(format: "count > 1")
        let opened = XCTNSPredicateExpectation(predicate: predicate, object: app.windows)
        if XCTWaiter.wait(for: [opened], timeout: 5) != .completed {
            XCTFail("[settings] ⌘, did not open the Settings window")
        }
        settle(1)
        // The key (frontmost) window is the Settings one.
        capture(app, "06-settings", window: app.windows.element(boundBy: 0))
        app.terminate()
    }

    /// The real flow, no seeded data: Plan It on the decision card stores the
    /// plan on device, the sidebar's Plans section appears, and its row opens
    /// the plan sheet.
    func test08Plans() {
        let app = launch()
        waitForResults(app, "plans")
        let planIt = app.descendants(matching: .any).matching(identifier: "planItButton").firstMatch
        guard planIt.waitForExistence(timeout: 5) else {
            XCTFail("[plans] no Plan It button on the decision card")
            capture(app, "08-plans-sidebar")
            app.terminate()
            return
        }
        planIt.click()
        let row = app.descendants(matching: .any).matching(identifier: "picnicPlanRow").firstMatch
        if !row.waitForExistence(timeout: 5) {
            XCTFail("[plans] Plan It added no row to the Plans section")
        }
        scrollIntoView(row, in: app)
        settle(1)
        capture(app, "08-plans-sidebar")

        if row.exists {
            row.click()
            if !app.sheets.firstMatch.waitForExistence(timeout: 5) {
                XCTFail("[plans] the plan row did not open the plan sheet")
            }
            settle(1)
            capture(app, "09-plan-sheet")
        }
        app.terminate()
    }

    /// Week plan for the saved spots (fixture favorites), lower in the
    /// sidebar. Plus: on Free the section is a locked "See the best times".
    func test09WeekPlan() {
        let app = launch(plan: "plus")
        waitForResults(app, "week plan")
        let row = app.descendants(matching: .any).matching(identifier: "planRow").firstMatch
        if !row.waitForExistence(timeout: 10) {
            XCTFail("[week plan] no week plan rows for the saved spots")
        }
        scrollIntoView(row, in: app)
        settle(1)
        capture(app, "10-week-plan")
        app.terminate()
    }

    /// Scrolls the sidebar until `element` is on screen (macOS does not
    /// scroll for a screenshot by itself).
    private func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication) {
        guard element.exists else { return }
        let list = app.outlines.firstMatch.exists ? app.outlines.firstMatch : app.tables.firstMatch
        guard list.exists else { return }
        for delta in [-120.0, 120.0] {
            var tries = 0
            while !element.isHittable && tries < 10 {
                list.scroll(byDeltaX: 0, deltaY: delta)
                tries += 1
            }
            if element.isHittable { return }
        }
    }

    /// Responses held back 30 s: the sidebar while Best Now loads.
    func test10Loading() {
        let app = launch(extra: ["-UITestDelay", "30"])
        settle(4)
        capture(app, "11-loading")
        app.terminate()
    }

    /// Every request fails as "not connected to the internet".
    func test11Offline() {
        let app = launch(extra: ["-UITestOffline", "YES"])
        settle(8)
        capture(app, "12-offline")
        app.terminate()
    }

    func test07German() {
        let app = launch(language: "de")
        waitForResults(app, "de")
        capture(app, "07-explore-de")
        app.terminate()
    }
}
#endif
