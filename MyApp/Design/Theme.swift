import SwiftUI
#if os(iOS)
import UIKit
typealias PlatformColor = UIColor
#elseif os(macOS)
import AppKit
typealias PlatformColor = NSColor
#endif

// Design tokens — UI_SPEC §2. One brand color (Meadow), everything else is a
// system semantic color. No gradients, no shadows.
//
// Names are `brand*` on purpose: the asset catalog already generates
// `Color.accent` / `Color.meadowSoft` symbols, so custom names avoid clashes.

extension Color {
    /// Meadow — tint, primary actions, Great/Good tiers, park outlines.
    static let brand = Color("AccentColor")
    /// Light Meadow wash behind the score number / selected state.
    /// Only for large or bold text on top (contrast ≈ 4.4:1 in light mode).
    static let brandSoft = Color("MeadowSoft")
}

extension PlatformColor {
    static var brand: PlatformColor { PlatformColor(named: "AccentColor") ?? .systemGreen }
}

// MARK: - Score tiers

/// Score → display tier. Great/Good share Meadow and differ by number, label
/// and ring fill (two adjacent greens are hard to tell apart). Low scores are
/// gray, never red — red is reserved for destructive actions.
enum ScoreTier {
    case great, good, fair, poor

    init(score: Int) {
        switch score {
        case 80...: self = .great
        case 60..<80: self = .good
        case 40..<60: self = .fair
        default: self = .poor
        }
    }

    var color: Color {
        switch self {
        case .great, .good: .brand
        case .fair: .orange
        case .poor: .secondary
        }
    }

    var platformColor: PlatformColor {
        switch self {
        case .great, .good: .brand
        case .fair: .systemOrange
        case .poor: .systemGray
        }
    }

    var label: String {
        switch self {
        case .great: String(localized: "Great")
        case .good: String(localized: "Good")
        case .fair: String(localized: "Fair")
        case .poor: String(localized: "Poor")
        }
    }
}

/// Hard cap reason → symbol shown next to a capped score.
enum CapStyle {
    static func symbol(_ capReason: String?) -> String? {
        switch capReason {
        case "rain": "cloud.rain.fill"
        case "heat": "thermometer.sun.fill"
        case "cold": "thermometer.snowflake"
        case "dark": "moon.fill"
        case "twilight": "sun.horizon.fill"
        default: nil
        }
    }
}

// MARK: - Spot kinds & amenities

enum KindStyle {
    static func symbol(_ kind: String) -> String {
        switch kind {
        case "park": "tree.fill"
        case "beach": "beach.umbrella.fill"
        case "site": "basket.fill"
        case "table": "table.furniture.fill"
        default: "mappin"
        }
    }

    static func label(_ kind: String) -> String {
        switch kind {
        case "park": String(localized: "Park")
        case "beach": String(localized: "Beach")
        case "site": String(localized: "Picnic area")
        case "table": String(localized: "Picnic table")
        default: String(localized: "Spot")
        }
    }
}

enum AmenityStyle {
    static func symbol(_ type: String) -> String {
        switch type {
        case "toilet": "toilet.fill"
        case "water": "drop.fill"
        case "bbq": "flame.fill"
        case "playground": "figure.play"
        case "shelter": "tent.fill"
        case "parking": "parkingsign"
        case "bicycle_parking": "bicycle"
        case "dog_area": "dog.fill"
        default: "mappin"
        }
    }

    static func label(_ type: String) -> String {
        switch type {
        case "toilet": String(localized: "Toilets")
        case "water": String(localized: "Drinking water")
        case "bbq": String(localized: "BBQ")
        case "playground": String(localized: "Playground")
        case "shelter": String(localized: "Shelter")
        case "parking": String(localized: "Parking")
        case "bicycle_parking": String(localized: "Bike parking")
        case "dog_area": String(localized: "Dog area")
        default: type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

// MARK: - Platform-neutral view helpers

extension View {
    /// Inline navigation title on iOS; no-op on macOS (no title display modes).
    @ViewBuilder
    func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Grouped list look: insetGrouped on iOS, inset on macOS.
    @ViewBuilder
    func groupedList() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }
}
