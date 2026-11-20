import StoreKit
import SwiftUI

/// Where the paywall was opened from — picks the one-line headline and goes
/// into `paywall_shown` so we can see which touch point converts.
enum PaywallReason: String, Identifiable {
    case general, forecast, picks, saved, alerts, planner, plans, getaways
    var id: Self { self }

    var headline: String {
        switch self {
        case .general: String(localized: "Pick the best hour for every picnic.")
        case .forecast: String(localized: "Plan the whole week, hour by hour.")
        case .picks: String(localized: "See every good spot nearby, not just the top three.")
        case .saved: String(localized: "Save as many places as you like.")
        case .alerts: String(localized: "Get alerts for all your favorite spots.")
        case .planner: String(localized: "See the best picnic times across your places this week.")
        case .plans: String(localized: "Get forecast alerts for up to \(PlanSyncStore.plusLimit) plans at once.")
        case .getaways: String(localized: "Find the best weekend weather across every city.")
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

    /// What the rows show, in App Store Connect order.
    @State private var options: [PlanOption] = []
    /// The StoreKit products behind `options`, for `buy` (empty in fixture mode).
    @State private var products: [String: Product] = [:]
    @State private var purchasingID: String?
    @State private var notice: String?

    var body: some View {
        // Custom purchase UI instead of SubscriptionStoreView: StoreKit's
        // ready-made view cannot pass `appAccountToken`, and the backend
        // requires it to bind the transaction to this device.
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pickhour Plus")
                    .font(.largeTitle.bold())
                Text(reason.headline)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Opened from a locked day: that day's real best hour, which
            // Free already sees in the week strip — no made-up numbers.
            if reason == .forecast, let teaser = app.paywallTeaser {
                Text(teaser.text)
                    .font(.headline)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            PlanComparison()
            productList
            if let notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            // One line when it fits; stacked at large text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { footerLinks }
                VStack(alignment: .leading, spacing: 8) { footerLinks }
            }
            .font(.footnote)
            Text("Cancel anytime in Settings. Works on iPhone, iPad and Mac.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .frame(maxWidth: .infinity)
        .padding(24)
        .task {
            app.paywallDidAppear(reason)
            app.track("paywall_shown", ["reason": .string(reason.rawValue)])
            await loadProducts()
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 640)
        #endif
    }

    @ViewBuilder
    private var productList: some View {
        if options.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else {
            ForEach(options) { product in
                Button {
                    Task { await buy(product.id) }
                } label: {
                    HStack {
                        let saving = savings(product)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(product.displayName)
                                    .font(.headline)
                                if let saving {
                                    Text("Save \(saving.percent)%")
                                        .font(.caption.bold())
                                        .foregroundStyle(.tint)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(.tint.opacity(0.15), in: Capsule())
                                }
                            }
                            let subtitle = [periodLabel(product), saving.map {
                                String(localized: "\($0.perMonth)/month")
                            }].compactMap { $0 }.joined(separator: " · ")
                            if !subtitle.isEmpty {
                                Text(verbatim: subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if purchasingID == product.id {
                            ProgressView()
                        } else {
                            Text(product.displayPrice)
                                .font(.headline.monospacedDigit())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(purchasingID != nil)
            }
        }
    }

    /// Products in the order declared in App Store Connect. UI-test fixture
    /// mode has no StoreKit products, so it shows the launch prices instead
    /// (screenshots for App Review and the product page).
    private func loadProducts() async {
        if UITestFixtures.isActive {
            options = PlanOption.fixtures
            return
        }
        let loaded = (try? await Product.products(for: Self.productIDs)) ?? []
        let ordered = Self.productIDs.compactMap { id in loaded.first { $0.id == id } }
        products = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
        options = ordered.map(PlanOption.init)
    }

    /// Longer plans vs. paying monthly for the same span, from the live
    /// StoreKit prices: the badge stays true whatever the prices are set to
    /// in App Store Connect. Nil under 5% (not worth a badge) or without a
    /// monthly product to compare against.
    private func savings(_ product: PlanOption) -> (percent: Int, perMonth: String)? {
        guard let months = product.months, months > 1,
              let monthly = options.first(where: { $0.months == 1 }),
              monthly.price > 0
        else { return nil }
        let ratio = 1 - product.price / (monthly.price * Decimal(months))
        let percent = Int((NSDecimalNumber(decimal: ratio).doubleValue * 100).rounded())
        guard percent >= 5 else { return nil }
        let perMonth = (product.price / Decimal(months)).formatted(product.priceFormatStyle)
        return (percent, perMonth)
    }

    private func periodLabel(_ product: PlanOption) -> String? {
        guard let unit = product.periodUnit else { return nil }
        // Whole phrases per unit: "every 3 \(unit)s" only pluralises in English.
        let n = product.periodValue
        switch unit {
        case .day: return n == 1 ? String(localized: "per day") : String(localized: "every \(n) days")
        case .week: return n == 1 ? String(localized: "per week") : String(localized: "every \(n) weeks")
        case .month: return n == 1 ? String(localized: "per month") : String(localized: "every \(n) months")
        case .year: return n == 1 ? String(localized: "per year") : String(localized: "every \(n) years")
        @unknown default: return nil
        }
    }

    private func buy(_ id: String) async {
        // Fixture mode: no StoreKit product, nothing to buy.
        guard let product = products[id] else { return }
        purchasingID = product.id
        notice = nil
        defer { purchasingID = nil }
        do {
            // appAccountToken binds this transaction to our device UUID —
            // the backend rejects links without a matching token.
            let result = try await product.purchase(options: [
                .appAccountToken(DeviceIdentity.deviceID),
            ])
            switch result {
            case .success(let verification):
                // The signed JWS lives on the VerificationResult, not on the
                // decoded Transaction.
                guard case .verified(let transaction) = verification else {
                    notice = String(localized: "Purchase could not be verified. Try again or contact support.")
                    break
                }
                await app.link(signedTransaction: verification.jwsRepresentation)
                await transaction.finish()
                app.paywallDidPurchase()
                app.track("plus_purchased", ["reason": .string(reason.rawValue)])
                dismiss()
            case .userCancelled:
                break
            case .pending:
                notice = String(localized: "Purchase pending approval.")
            @unknown default:
                break
            }
        } catch {
            notice = error.localizedDescription
        }
    }

    /// Restore + the policy links App Review requires next to a subscription
    /// offer (Guideline 3.1.2).
    @ViewBuilder
    private var footerLinks: some View {
        Button("Restore purchases") { Task { await app.restorePurchases() } }
        if let url = AppConfig.privacyPolicyURL {
            Link("Privacy Policy", destination: url)
        }
        if let url = AppConfig.termsOfUseURL {
            Link("Terms of Use", destination: url)
        }
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
            Row(feature: String(localized: "Plans with forecast alerts"),
                free: "\(PlanSyncStore.freeLimit)",
                plus: "\(PlanSyncStore.plusLimit)"),
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
                // A GridRow is not a view of its own: accessibility modifiers
                // on it reach no element (VoiceOver read three loose cells and
                // UI tests found no `plan.row`). The feature cell carries the
                // whole row; the value cells are folded into its label.
                GridRow {
                    Text(row.feature)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(Text("\(row.feature), Free: \(row.free ?? String(localized: "not included")), Plus: \(row.plus)"))
                        .accessibilityIdentifier("plan.row")
                    Text(row.free ?? "—")
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(row.plus)
                        .fontWeight(.semibold)
                        .accessibilityHidden(true)
                }
                .font(.subheadline)
                .monospacedDigit()
            }
        }
    }
}

/// One row of the paywall: a StoreKit product, or fixed launch prices in
/// UI-test fixture mode (no StoreKit there). Holds only what the rows and the
/// "Save N%" badge read.
struct PlanOption: Identifiable {
    let id: String
    let displayName: String
    let displayPrice: String
    let price: Decimal
    let priceFormatStyle: Decimal.FormatStyle.Currency
    /// nil for a non-subscription product.
    let periodUnit: Product.SubscriptionPeriod.Unit?
    let periodValue: Int

    init(_ product: Product) {
        id = product.id
        displayName = product.displayName
        displayPrice = product.displayPrice
        price = product.price
        priceFormatStyle = product.priceFormatStyle
        periodUnit = product.subscription?.subscriptionPeriod.unit
        periodValue = product.subscription?.subscriptionPeriod.value ?? 0
    }

    private init(id: String, displayName: String, usd: String,
                 unit: Product.SubscriptionPeriod.Unit) {
        let style = Decimal.FormatStyle.Currency(code: "USD", locale: Locale(identifier: "en_US"))
        let price = Decimal(string: usd, locale: Locale(identifier: "en_US_POSIX")) ?? 0
        self.id = id
        self.displayName = displayName
        self.displayPrice = price.formatted(style)
        self.price = price
        self.priceFormatStyle = style
        self.periodUnit = unit
        self.periodValue = 1
    }

    /// Subscription length in months; nil for products billed by day/week.
    var months: Int? {
        switch periodUnit {
        case .month?: periodValue
        case .year?: periodValue * 12
        default: nil
        }
    }

    /// Launch prices and App Store Connect display names (US storefront).
    static let fixtures: [PlanOption] = [
        PlanOption(id: PaywallSheet.productIDs[0], displayName: "Plus Yearly", usd: "29.99", unit: .year),
        PlanOption(id: PaywallSheet.productIDs[1], displayName: "Plus Monthly", usd: "4.99", unit: .month),
    ]
}
