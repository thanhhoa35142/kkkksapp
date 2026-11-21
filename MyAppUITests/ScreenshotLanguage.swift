import Foundation

/// The language the screenshot suites run in. CI sets it per run with
/// `TEST_RUNNER_SCREENSHOT_LANG=nl|de|es` (xcodebuild hands `TEST_RUNNER_*`
/// variables to the test runner without the prefix); unset means English.
enum ScreenshotLanguage {
    static let locales = ["en": "en_US", "nl": "nl_NL", "de": "de_DE", "es": "es_ES"]

    static let current: String = {
        let value = ProcessInfo.processInfo.environment["SCREENSHOT_LANG"] ?? "en"
        return locales[value] == nil ? "en" : value
    }()

    static func locale(_ language: String) -> String { locales[language] ?? "en_US" }

    /// `english` as the app shows it in `language` (labels the tests tap).
    static func text(_ english: String, in language: String) -> String {
        ScreenshotStrings.table[english]?[language] ?? english
    }

    /// The fixed text before the first placeholder of a format key, e.g.
    /// "Warum" for "Why %lld?" in German: labels like "Why 83?" start with it.
    static func prefix(of formatKey: String, in language: String) -> String {
        let format = text(formatKey, in: language)
        return String(format[..<(format.range(of: "%")?.lowerBound ?? format.endIndex)])
            .trimmingCharacters(in: .whitespaces)
    }
}
