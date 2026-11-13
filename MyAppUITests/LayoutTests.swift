#if os(iOS)
import XCTest

/// Layout checks on fixture data (`-UITestFixtures`, no backend), at three
/// Dynamic Type sizes. Catches what breaks first on small phones and large text:
/// - text cut off / pushed off screen, overlapping elements,
/// - uneven columns or gaps (week strip, action buttons, list rows),
/// - tap targets under 44 pt (Apple HIG) via the system accessibility audit,
/// - primary actions out of thumb reach (needing a scroll, or stuck at the top).
///
/// Fixture names are long on purpose ("Koningin Wilhelminapark en Speeltuin
/// De Bolderik aan de Amstel") so wrapping problems show up.
final class LayoutTests: XCTestCase {
    enum TextSize: String, CaseIterable {
        case standard = "UICTContentSizeCategoryL"
        case xxxLarge = "UICTContentSizeCategoryXXXL"
        case ax3 = "UICTContentSizeCategoryAccessibilityXXXL"

        var isAccessibility: Bool { self == .ax3 }
    }

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func launch(_ size: TextSize, plan: String = "free") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestFixtures",
            "-UITestPlan", plan,
            "-onboardingDone", "YES",
            "-UIPreferredContentSizeCategoryName", size.rawValue,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
        return app
    }

    // MARK: - Screens

    func testBestNow() throws {
        for size in TextSize.allCases {
            let app = launch(size)
            let rows = app.descendants(matching: .any).matching(identifier: "spotRow")
            XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "[\(size)] Best Now rows never loaded")

            Layout.assertNothingOffScreenHorizontally(app, "\(size) Best Now")
            Layout.assertNoOverlap(Layout.visible(rows, in: app), "\(size) Best Now rows")
            Layout.assertEvenVerticalGaps(Layout.visible(rows, in: app), tolerance: 6, "\(size) Best Now rows")
            // No big empty band above the first result.
            let first = rows.firstMatch.frame
            XCTAssertLessThan(first.minY, Layout.window(app).height * 0.45,
                              "[\(size)] first result starts too low (\(first.minY)) — empty space above the list")
            Layout.audit(app, "\(size) Best Now")
            app.terminate()
        }
    }

    func testSpotDetail() throws {
        for size in TextSize.allCases {
            let app = launch(size)
            let row = app.descendants(matching: .any).matching(identifier: "spotRow").element(boundBy: 1)
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            row.tap()

            let directions = app.buttons["spotAction.directions"]
            XCTAssertTrue(directions.waitForExistence(timeout: 10), "[\(size)] Spot Detail didn't open")
            let actions = ["spotAction.directions", "spotAction.alert", "spotAction.report"].map { app.buttons[$0] }

            if size.isAccessibility {
                // Stacked: same width, one under the other.
                Layout.assertEqualWidths(actions, tolerance: 1.5, "\(size) action buttons (stacked)")
            } else {
                Layout.assertEqualWidths(actions, tolerance: 1.5, "\(size) action buttons")
                Layout.assertEvenHorizontalGaps(actions, tolerance: 1.5, "\(size) action buttons")
                // Thumb reach: the main action is on screen without scrolling,
                // and not crammed into the top bar area.
                Layout.assertInThumbReach(directions, app, "\(size) Directions")
            }
            Layout.assertNoOverlap(actions, "\(size) action buttons")

            // Week strip: 7 equal columns, evenly spaced, inside the screen.
            let strip = (0..<7).map { app.buttons["weekStrip.day.\($0)"] }
            Layout.scrollTo(strip[0], in: app)
            if strip[0].exists {
                if size.isAccessibility {
                    Layout.assertEqualWidths(strip.filter(\.exists), tolerance: 1.5, "\(size) week strip rows")
                } else {
                    Layout.assertEqualWidths(strip.filter(\.exists), tolerance: 1.5, "\(size) week strip columns")
                    Layout.assertEvenHorizontalGaps(strip.filter(\.exists), tolerance: 1.5, "\(size) week strip columns")
                    for day in strip where day.exists {
                        XCTAssertGreaterThanOrEqual(day.frame.width, 40, "[\(size)] week strip column too narrow to tap")
                    }
                }
            } else {
                XCTFail("[\(size)] week strip not found")
            }

            Layout.assertNothingOffScreenHorizontally(app, "\(size) Spot Detail")
            Layout.audit(app, "\(size) Spot Detail")
            app.terminate()
        }
    }

    func testSavedWithWeekPlan() throws {
        for size in TextSize.allCases {
            let app = launch(size, plan: "plus")
            app.tabBars.buttons["Saved"].tap()
            let planRows = app.descendants(matching: .any).matching(identifier: "planRow")
            XCTAssertTrue(planRows.firstMatch.waitForExistence(timeout: 15), "[\(size)] This Week never loaded")
            Layout.assertNoOverlap(Layout.visible(planRows, in: app), "\(size) This Week rows")
            Layout.assertNothingOffScreenHorizontally(app, "\(size) Saved")
            Layout.audit(app, "\(size) Saved")
            app.terminate()
        }
    }

    func testPaywall() throws {
        for size in TextSize.allCases {
            let app = launch(size)
            let more = app.buttons["See more picks with Plus"]
            Layout.scrollTo(more, in: app)
            XCTAssertTrue(more.waitForExistence(timeout: 10), "[\(size)] paywall entry missing")
            more.tap()
            let rows = app.descendants(matching: .any).matching(identifier: "plan.row")
            XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "[\(size)] comparison table missing")
            Layout.assertNothingOffScreenHorizontally(app, "\(size) Paywall")
            Layout.audit(app, "\(size) Paywall", ignoringSystemUI: true)
            app.terminate()
        }
    }

    func testOnboardingPrimaryButtonsAtTheBottom() throws {
        for size in TextSize.allCases {
            let app = XCUIApplication()
            app.launchArguments = ["-UITestFixtures", "-onboardingDone", "NO",
                                   "-UIPreferredContentSizeCategoryName", size.rawValue,
                                   "-AppleLanguages", "(en)"]
            app.launch()
            let next = app.buttons["Continue"]
            XCTAssertTrue(next.waitForExistence(timeout: 10), "[\(size)] Welcome not shown")
            let w = Layout.window(app)
            // Primary button sits in the bottom third, full width, ≥ 44 pt.
            if !size.isAccessibility {
                XCTAssertGreaterThan(next.frame.minY, w.height * 0.66, "[\(size)] Continue not in the thumb zone: \(next.frame)")
            }
            XCTAssertTrue(next.isHittable, "[\(size)] Continue needs scrolling")
            XCTAssertGreaterThanOrEqual(next.frame.height, 44, "[\(size)] Continue under 44 pt")
            XCTAssertGreaterThan(next.frame.width, w.width * 0.6, "[\(size)] Continue should span the width")
            Layout.assertNothingOffScreenHorizontally(app, "\(size) Welcome")
            Layout.audit(app, "\(size) Welcome")

            next.tap()
            let city = app.buttons["Choose a City"]
            XCTAssertTrue(city.waitForExistence(timeout: 5), "[\(size)] Where step not shown")
            Layout.assertEqualWidths([app.buttons["Use My Location"], city], tolerance: 1.5, "\(size) Where buttons")
            Layout.assertNothingOffScreenHorizontally(app, "\(size) Where")
            app.terminate()
        }
    }

    func testTabBarInThumbZone() throws {
        let app = launch(.standard)
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        let window = Layout.window(app)
        XCTAssertGreaterThan(tabBar.frame.minY, window.height * 0.8, "tab bar should sit at the bottom edge")
        for button in tabBar.buttons.allElementsBoundByIndex {
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, "tab \(button.label) under 44 pt")
        }
    }
}

// MARK: - Geometry helpers

enum Layout {
    static func window(_ app: XCUIApplication) -> CGRect { app.windows.firstMatch.frame }

    /// Elements currently inside the window (lists keep off-screen rows).
    static func visible(_ query: XCUIElementQuery, in app: XCUIApplication) -> [XCUIElement] {
        let w = window(app)
        return query.allElementsBoundByIndex.filter { $0.exists && w.intersects($0.frame) && !$0.frame.isEmpty }
    }

    /// Scrolls the main scroll view until `element` is hittable (max 6 swipes).
    static func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        var tries = 0
        while !(element.exists && element.isHittable) && tries < 6 {
            app.swipeUp(velocity: .slow)
            tries += 1
        }
    }

    /// Every visible text and button stays inside the screen width —
    /// a sign that nothing is pushed out by a long word or a fixed width.
    static func assertNothingOffScreenHorizontally(_ app: XCUIApplication, _ context: String,
                                                   file: StaticString = #filePath, line: UInt = #line) {
        let w = window(app)
        let elements = visible(app.staticTexts, in: app) + visible(app.buttons, in: app)
        for e in elements where e.frame.height > 0 {
            let f = e.frame
            if f.minX < w.minX - 1 || f.maxX > w.maxX + 1 {
                XCTFail("[\(context)] '\(e.label)' runs off screen horizontally: \(f) in \(w)", file: file, line: line)
            }
        }
    }

    static func assertNoOverlap(_ elements: [XCUIElement], _ context: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        let frames = elements.filter(\.exists).map(\.frame)
        for i in frames.indices {
            for j in frames.indices where j > i {
                let overlap = frames[i].intersection(frames[j])
                if !overlap.isNull, overlap.width * overlap.height > 4 {
                    XCTFail("[\(context)] items \(i) and \(j) overlap: \(frames[i]) / \(frames[j])", file: file, line: line)
                }
            }
        }
    }

    static func assertEqualWidths(_ elements: [XCUIElement], tolerance: CGFloat, _ context: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let widths = elements.filter(\.exists).map(\.frame.width)
        guard let lo = widths.min(), let hi = widths.max() else {
            return XCTFail("[\(context)] nothing to measure", file: file, line: line)
        }
        XCTAssertLessThanOrEqual(hi - lo, tolerance, "[\(context)] uneven widths \(widths)", file: file, line: line)
    }

    static func assertEvenHorizontalGaps(_ elements: [XCUIElement], tolerance: CGFloat, _ context: String,
                                         file: StaticString = #filePath, line: UInt = #line) {
        let frames = elements.filter(\.exists).map(\.frame).sorted { $0.minX < $1.minX }
        let gaps = zip(frames, frames.dropFirst()).map { $1.minX - $0.maxX }
        guard let lo = gaps.min(), let hi = gaps.max() else { return }
        XCTAssertLessThanOrEqual(hi - lo, tolerance, "[\(context)] uneven gaps \(gaps)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(lo, -0.5, "[\(context)] items overlap horizontally \(gaps)", file: file, line: line)
    }

    /// Rows in one list should be spaced alike (row heights may differ).
    static func assertEvenVerticalGaps(_ elements: [XCUIElement], tolerance: CGFloat, _ context: String,
                                       file: StaticString = #filePath, line: UInt = #line) {
        let frames = elements.map(\.frame).sorted { $0.minY < $1.minY }
        let gaps = zip(frames, frames.dropFirst()).map { $1.minY - $0.maxY }
        guard gaps.count >= 2, let lo = gaps.min(), let hi = gaps.max() else { return }
        XCTAssertLessThanOrEqual(hi - lo, tolerance, "[\(context)] uneven row gaps \(gaps)", file: file, line: line)
    }

    /// Thumb zone on a phone held one-handed: fully on screen (no scroll
    /// needed) and below the top fifth (status bar + nav bar area).
    static func assertInThumbReach(_ element: XCUIElement, _ app: XCUIApplication, _ context: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let w = window(app)
        let f = element.frame
        XCTAssertTrue(element.isHittable, "[\(context)] not tappable without scrolling", file: file, line: line)
        XCTAssertLessThanOrEqual(f.maxY, w.maxY, "[\(context)] below the fold: \(f)", file: file, line: line)
        XCTAssertGreaterThan(f.minY, w.height * 0.2, "[\(context)] too high to reach one-handed: \(f)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(f.height, 44, "[\(context)] shorter than 44 pt", file: file, line: line)
    }

    /// System audit (iOS 17+): clipped text, tap targets < 44 pt, Dynamic Type
    /// support, contrast. StoreKit's own view and the map are Apple's UI and
    /// are skipped when `ignoringSystemUI` is set.
    static func audit(_ app: XCUIApplication, _ context: String, ignoringSystemUI: Bool = false,
                      file: StaticString = #filePath, line: UInt = #line) {
        do {
            try app.performAccessibilityAudit(for: [.textClipped, .hitRegion, .dynamicType, .contrast]) { issue in
                guard let element = issue.element else { return true }      // nothing to point at
                if element.elementType == .map { return true }               // MapKit tiles
                if ignoringSystemUI && element.identifier.isEmpty { return true }
                XCTContext.runActivity(named: "[\(context)] \(issue.auditType): \(issue.compactDescription)") { _ in }
                return false
            }
        } catch {
            XCTFail("[\(context)] accessibility audit: \(error.localizedDescription)", file: file, line: line)
        }
    }
}
#endif
