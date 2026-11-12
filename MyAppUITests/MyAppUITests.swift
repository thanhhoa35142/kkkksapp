import XCTest

final class MyAppUITests: XCTestCase {

    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Pickhour"].waitForExistence(timeout: 5))
    }
}
