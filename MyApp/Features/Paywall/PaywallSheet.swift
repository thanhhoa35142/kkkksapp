import StoreKit
import SwiftUI

/// Where the paywall was opened from — picks the one-line headline and goes
/// into `paywall_shown` so we can see which touch point converts.
enum PaywallReason: String, Identifiable {
    case general, forecast, picks, saved, alerts, planner
    var id: Self { self }

    var headline: String {
        switch self {
        case .general: String(localized: "Pick the best hour for every picnic.")
        case .forecast: String(localized: "Plan the whole week, hour by hour.")
        case .picks: String(localized: "See every good spot nearby, not just the top three.")
        case .saved: String(localized: "Save as many places as you like.")
        case .alerts: String(localized: "Get alerts for all your favorite spots.")
        case .planner: String(localized: "See the best picnic times across your places this week.")
        }
    }
}

/// S11 · Paywall — StoreKit's own subscription view with a plain Free/Plus
/// comparison above it. No sparkles, crowns or illustrations (UI_SPEC §0).
/// Lists only what ships today (spec §15 "Đã có trong code"); add rows as
/// Plus features land — never advertise unshipped ones (App Review 2.3).
/// Opened only from Plus touch points, never on its own.
struct PaywallSheet: View {
    /// Must match App Store Connect (backend docs/API.md example ids).
    static let productIDs = ["com.pickhour.plus.yearly", "com.pickhour.plus.monthly"]

    var reason: PaywallReason = .general

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubscriptionStoreView(productIDs: Self.productIDs) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pickhour Plus")
                        .font(.largeTitle.bold())
                    Text(reason.headline)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PlanComparison()
                Text("Cancel anytime in Settings. Works on iPhone, iPad and Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .storeButton(.visible, for: .restorePurchases)
        .storeButton(.visible, for: .policies)
        .storeButton(.visible, for: .cancellation)
        .onInAppPurchaseCompletion { _, result in
            if case .success(.success(let verification)) = result {
                await app.link(signedTransaction: verification.jwsRepresentation)
                if case .verified(let transaction) = verification { await transaction.finish() }
                app.paywallDidPurchase()
                app.track("plus_purchased", ["reason": .string(reason.rawValue)])
                dismiss()
            }
        }
        .task {
            app.paywallDidAppear(reason)
            app.track("paywall_shown", ["reason": .string(reason.rawValue)])
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 640)
        #endif
    }
}

/// Three-column table: feature · Free · Plus. Each row reads as one
/// VoiceOver element ("Hourly scores, Free: today and tomorrow, Plus: 7 days").
private struct PlanComparison: View {
    private struct Row: Identifiable {
        /// `free` nil = not on Free (shows a dash, VoiceOver says "not included").
        let feature: String, free: String?, plus: String
        var id: String { feature }
    }

    private var rows: [Row] {
        [
            Row(feature: String(localized: "Best times this week"),
                free: nil,
                plus: String(localized: "Included")),
            Row(feature: String(localized: "Weekend plan on Thursday"),
                free: nil,
                plus: String(localized: "Included")),
            Row(feature: String(localized: "Hourly scores"),
                free: String(localized: "Today and tomorrow"),
                plus: String(localized: "7 days")),
            Row(feature: String(localized: "Best nearby"),
                free: "\(BestNowModel.freeLimit)",
                plus: "\(BestNowModel.plusLimit)"),
            Row(feature: String(localized: "Score alerts"),
                free: "\(AlertsStore.freeLimit)",
                plus: String(localized: "Unlimited")),
            Row(feature: String(localized: "Saved places"),
                free: "\(Favorites.freeLimit)",
                plus: String(localized: "Unlimited")),
        ]
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Text("Free")
                    .foregroundStyle(.secondary)
                Text("Plus")
                    .foregroundStyle(Color.brand)
            }
            .font(.subheadline.weight(.semibold))
            .accessibilityHidden(true)

            ForEach(rows) { row in
                Divider()
                GridRow {
                    Text(row.feature)
                    Text(row.free ?? "—")
                        .foregroundStyle(.secondary)
                    Text(row.plus)
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .monospacedDigit()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(row.feature), Free: \(row.free ?? String(localized: "not included")), Plus: \(row.plus)"))
                .accessibilityIdentifier("plan.row")
            }
        }
    }
}
