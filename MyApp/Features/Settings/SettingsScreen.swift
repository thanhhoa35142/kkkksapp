import CoreLocation
import SwiftData
import StoreKit
import SwiftUI
import UserNotifications

/// S4 · Settings — text-only rows, no colored icon squares (UI_SPEC §2).
/// iPhone: a tab. iPad: sheet from the sidebar. Mac: the Settings window (⌘,).
struct SettingsScreen: View {
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    @AppStorage(UnitPreference.temperatureKey) private var temperature = UnitPreference.automatic.rawValue
    @AppStorage(UnitPreference.distanceKey) private var distance = UnitPreference.automatic.rawValue
    @AppStorage("onboardingDone") private var onboardingDone = true
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var confirmDelete = false
    @State private var isRestoring = false
    @State private var showManageSubscriptions = false

    var body: some View {
        Form {
            planSection
            unitsSection
            notificationsSection
            permissionsSection
            privacySection
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        #if os(iOS)
        .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        #endif
        .task { notificationStatus = await PushManager.shared.authorizationStatus() }
        .confirmationDialog("Delete your data?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete My Data", role: .destructive) {
                Task {
                    try? context.delete(model: FavoriteSpot.self)
                    try? context.delete(model: PicnicPlan.self)
                    await app.deleteMyData()
                    onboardingDone = false
                }
            }
        } message: {
            Text("Removes your saved places, plans, alerts and this device's record from Pickhour. This can't be undone.")
        }
    }

    private var planSection: some View {
        Section("Plan") {
            if app.isPlus, let entitlement = app.entitlement {
                LabeledContent("Pickhour Plus") {
                    if let expires = entitlement.expiresAt {
                        Text(entitlement.autoRenew == true ? "Renews \(expires.formatted(date: .abbreviated, time: .omitted))"
                                                            : "Ends \(expires.formatted(date: .abbreviated, time: .omitted))")
                    }
                }
                if entitlement.isFamilyShared {
                    Text("Shared with you through Family Sharing")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Manage Subscription") { manageSubscription() }
                }
            } else {
                LabeledContent("Current plan", value: String(localized: "Free"))
                Button("Upgrade to Plus") { app.paywall = .general }
            }
            Button(isRestoring ? "Restoring…" : "Restore Purchases") {
                Task {
                    isRestoring = true
                    await app.restorePurchases()
                    isRestoring = false
                }
            }
            .disabled(isRestoring)
        }
    }

    private var unitsSection: some View {
        Section("Units") {
            Picker("Temperature", selection: $temperature) {
                Text("Automatic").tag(UnitPreference.automatic.rawValue)
                Text("Celsius").tag(UnitPreference.metric.rawValue)
                Text("Fahrenheit").tag(UnitPreference.imperial.rawValue)
            }
            Picker("Distance", selection: $distance) {
                Text("Automatic").tag(UnitPreference.automatic.rawValue)
                Text("Kilometers").tag(UnitPreference.metric.rawValue)
                Text("Miles").tag(UnitPreference.imperial.rawValue)
            }
        }
        .pickerStyle(.menu)
    }

    private var notificationsSection: some View {
        Section {
            Toggle("Good-day tips", isOn: Binding(
                get: { app.nudge.isEnabled },
                set: { on in Task { await setGoodDayTips(on) } }
            ))
            .disabled(app.nudge.isBusy || (notificationStatus == .denied && !app.nudge.isEnabled))
        } header: {
            Text("Notifications")
        } footer: {
            if notificationStatus == .denied {
                Text("Notifications are off for Pickhour. Turn them on in System Settings to get good-day tips.")
            } else {
                Text("A notification when it's a great day for a picnic near you. At most twice a week. Your place is shared as an area of about 5 km², never as a point.")
            }
        }
    }

    private var permissionsSection: some View {
        Section {
            LabeledContent("Location", value: locationText)
            LabeledContent("Notifications", value: notificationText)
            Button("Open System Settings") { openSystemSettings() }
        } header: {
            Text("Permissions")
        } footer: {
            Text("Location is used only while the app is open and is never stored.")
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            if let url = AppConfig.privacyPolicyURL {
                Link("Privacy Policy", destination: url)
            }
            Button("Delete My Data", role: .destructive) { confirmDelete = true }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            NavigationLink("Data Sources") { DataSourcesView() }
            if let url = AppConfig.termsOfUseURL {
                Link("Terms of Use", destination: url)
            }
            if let url = AppConfig.feedbackMailURL {
                Link("Send Feedback", destination: url)
            }
            Button("Show Welcome Again") { onboardingDone = false }
            LabeledContent("Version", value: version)
        }
    }

    // MARK: Helpers

    private var locationText: String {
        if app.location.isAuthorized { return String(localized: "While Using") }
        if app.location.isDenied { return String(localized: "Off") }
        return String(localized: "Not Asked")
    }

    private var notificationText: String {
        switch notificationStatus {
        case .authorized: String(localized: "On")
        #if os(iOS)
        case .ephemeral: String(localized: "On")  // App Clips only; not on macOS
        #endif
        case .provisional: String(localized: "Delivered Quietly")
        case .denied: String(localized: "Off")
        default: String(localized: "Not Asked")
        }
    }

    /// Off: `DELETE /nudge`. On: the permission decides the consent — full is
    /// explicit, provisional stays quiet, never asked gets the system prompt
    /// (the user just asked for it), denied can't be turned on here.
    private func setGoodDayTips(_ on: Bool) async {
        guard on else {
            await app.nudge.disable()
            return
        }
        switch await PushManager.shared.authorizationStatus() {
        case .authorized:
            await app.nudge.enable(explicit: true)
        case .provisional:
            await app.nudge.enable(explicit: false)
        case .denied:
            break
        default:
            await app.nudge.turnOn()
        }
        notificationStatus = await PushManager.shared.authorizationStatus()
    }

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
        return "\(v) (\(b))"
    }

    /// iOS: StoreKit's own sheet. macOS has no such sheet, so it opens the
    /// App Store's subscriptions page (Apple's documented link).
    private func manageSubscription() {
        #if os(iOS)
        showManageSubscriptions = true
        #else
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") { openURL(url) }
        #endif
    }

    private func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        #else
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            openURL(url)
        }
        #endif
    }
}

/// Settings → About → Data Sources: licences and what each source feeds.
struct DataSourcesView: View {
    var body: some View {
        Form {
            Section {
                Text("Parks, beaches, picnic areas and amenities come from OpenStreetMap, © OpenStreetMap contributors, available under the Open Database License (ODbL).")
                Link("openstreetmap.org/copyright", destination: Self.osm)
            } header: {
                Text("Places")
            }
            Section {
                Text("Hourly weather comes from Apple Weather or Open-Meteo, depending on the region.")
                Link("Apple Weather data sources", destination: Self.appleWeather)
                Text("Open-Meteo weather data is available under CC BY 4.0. It is built on NOAA/NCEP GFS and GEFS forecasts and the Copernicus DEM GLO-90 elevation model.")
                Link("open-meteo.com", destination: Self.openMeteo)
            } header: {
                Text("Weather")
            }
            Section {
                Text("Crowd levels are estimated from the time of day, weather, holidays and reports from people nearby. They are not live data.")
            } header: {
                Text("Crowds")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Data Sources")
    }

    private static let osm = URL(string: "https://www.openstreetmap.org/copyright") ?? URL(fileURLWithPath: "/")
    private static let appleWeather = URL(string: "https://weatherkit.apple.com/legal-attribution.html")
        ?? URL(fileURLWithPath: "/")
    private static let openMeteo = URL(string: "https://open-meteo.com/") ?? URL(fileURLWithPath: "/")
}
