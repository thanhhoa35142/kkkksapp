import CoreLocation
import SwiftUI

/// Cities ranked by picnic weather on the days the user picks ("Where's
/// nice this weekend?"). A plain grouped list; the range lives in a toolbar
/// menu. Presented in a sheet with its own `NavigationStack` (`getawaysSheet`).
struct GetawaysScreen: View {
    let source: GetawaySource
    /// Dismisses the sheet.
    var onClose: () -> Void

    @Environment(AppState.self) private var app
    @State private var model = GetawaysModel()
    @State private var preset = GetawayPreset.thisWeekend
    @State private var custom: GetawayRange?
    @State private var showPicker = false
    @State private var trackedOpen = false

    private struct LoadKey: Equatable {
        let range: GetawayRange
        let plus: Bool
    }

    // MARK: Range

    private var range: GetawayRange {
        if preset == .custom, let custom { return custom }
        return GetawayRules.range(for: preset)
            ?? GetawayRange(start: GetawayRules.currentDay(), days: 1)
    }

    /// "This Weekend", or the picked days ("Sat, Nov 21 – Mon, Nov 23").
    private var rangeTitle: String {
        guard preset == .custom else { return preset.title }
        let current = range
        if current.days == 1 { return current.start.mediumLabel }
        return "\(current.start.mediumLabel) – \(current.end.mediumLabel)"
    }

    private func choose(_ next: GetawayPreset) {
        preset = next
        custom = nil
        app.track("getaways_range_changed", ["preset": .string(next.rawValue)])
    }

    private func pickDays(_ picked: GetawayRange) {
        preset = .custom
        custom = picked
        app.track("getaways_range_changed", ["preset": .string(GetawayPreset.custom.rawValue)])
    }

    // MARK: Rows

    /// Free sees the top 3 (the server clamps the same way).
    private var rows: [Getaway] {
        app.isPlus ? model.items : Array(model.items.prefix(GetawayRules.freeLimit))
    }

    private var showsUpgrade: Bool {
        !app.isPlus && model.items.count >= GetawayRules.freeLimit
    }

    private var homeSlug: String? {
        GetawayRules.homeSlug(place: app.place, packs: app.packs, fix: app.location.coordinate)
    }

    // MARK: Body

    var body: some View {
        List {
            content
        }
        .groupedList()
        .overlay { stateOverlay }
        .navigationTitle("Getaways")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { onClose() }
            }
            ToolbarItem(placement: .primaryAction) {
                rangeMenu
            }
        }
        .sheet(isPresented: $showPicker) {
            PickDaysSheet(initial: range, onPick: pickDays)
        }
        .task(id: LoadKey(range: range, plus: app.isPlus)) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if !model.items.isEmpty {
            Section {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, city in
                    cityButton(city, rank: index + 1)
                }
                if showsUpgrade {
                    Button("See All Cities with Plus") { upgrade() }
                }
            } header: {
                Text("Best Weather · \(rangeTitle)")
            } footer: {
                if GetawayRules.showsUncertaintyFooter(range) {
                    Text("Forecasts more than 3 days out can change.")
                }
            }
        }
    }

    private func cityButton(_ city: Getaway, rank: Int) -> some View {
        Button {
            GetawayNavigation.open(city, rank: rank, source: "screen", app: app)
            onClose()
        } label: {
            GetawayRow(city: city,
                       distanceMeters: GetawayRules.distanceMeters(from: app.location.coordinate, to: city),
                       isHome: city.slug == homeSlug)
        }
        .tint(.primary)
    }

    private func upgrade() {
        // Shown once the sheet is gone: the root paywall can't open over it.
        app.deferredPaywall = .getaways
        onClose()
    }

    // MARK: Empty, loading, failed

    @ViewBuilder
    private var stateOverlay: some View {
        if model.list == nil {
            switch model.phase {
            case .failed(let message):
                ContentUnavailableView {
                    Label("Can't load cities", systemImage: "wifi.slash")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            default:
                ProgressView()
            }
        } else if model.items.isEmpty {
            ContentUnavailableView {
                Label("No Great Weather in This Range", systemImage: "cloud.rain")
            } description: {
                Text("No city has good picnic weather on these days.")
            } actions: {
                Button("Try Other Days") { showPicker = true }
            }
        }
    }

    // MARK: Range menu

    private var rangeMenu: some View {
        Menu {
            ForEach(GetawayPreset.menuPresets) { item in
                presetButton(item)
            }
            Divider()
            Button(GetawayPreset.custom.title) { showPicker = true }
        } label: {
            Text(rangeTitle)
                .lineLimit(1)
        }
        .accessibilityLabel(Text("Days: \(rangeTitle)"))
    }

    @ViewBuilder
    private func presetButton(_ item: GetawayPreset) -> some View {
        let available = GetawayRules.isAvailable(item)
        Button {
            choose(item)
        } label: {
            if item == preset {
                Label(item.title, systemImage: "checkmark")
            } else {
                Text(item.title)
                if !available {
                    Text("Forecast not out yet")
                }
            }
        }
        .disabled(!available)
    }

    // MARK: Loading

    private func load() async {
        // "Your City" needs the packs when the place is the current location.
        if app.packs.isEmpty { await app.loadPacksIfNeeded() }
        await model.load(range: range, isPlus: app.isPlus)
        guard !trackedOpen, model.phase == .loaded else { return }
        trackedOpen = true
        let near = GetawayRules.nearCount(model.items, from: app.location.coordinate)
        app.track("getaways_opened", [
            "source": .string(source.rawValue),
            "nearCities": .number(Double(near)),
        ])
    }
}

// MARK: - Pick Days

/// "Pick Days…": a start day (today ... today + 5) and 1...3 days, ending
/// by the 7-day forecast horizon.
private struct PickDaysSheet: View {
    let onPick: (GetawayRange) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var days: Int

    init(initial: GetawayRange, onPick: @escaping (GetawayRange) -> Void) {
        self.onPick = onPick
        _start = State(initialValue: initial.start.date(in: .current))
        _days = State(initialValue: initial.days)
    }

    private var bounds: ClosedRange<Date> {
        let starts = GetawayRules.pickableStarts()
        return starts.lowerBound.date(in: .current)...starts.upperBound.date(in: .current)
    }

    private var startDay: CivilDay {
        CivilDay(start, in: .current)
    }

    private var allowedDays: Int {
        GetawayRules.maxDays(from: startDay)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Start", selection: $start, in: bounds, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                Picker("Days", selection: $days) {
                    ForEach(1...allowedDays, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.segmented)
            }
            .formStyle(.grouped)
            .navigationTitle("Pick Days")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onPick(GetawayRules.clamped(GetawayRange(start: startDay, days: days)))
                        dismiss()
                    }
                }
            }
            .onChange(of: start) { _, _ in
                days = min(days, allowedDays)
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Sheet

extension View {
    /// Presents Getaways when `AppState.getawaysSource` is set, in its own
    /// `NavigationStack`. A paywall asked for inside it opens after it closes.
    /// `sized`: a minimum size for the Mac / iPad window.
    func getawaysSheet(sized: Bool = false) -> some View {
        modifier(GetawaysSheetModifier(sized: sized))
    }
}

private struct GetawaysSheetModifier: ViewModifier {
    let sized: Bool

    @Environment(AppState.self) private var app

    @ViewBuilder
    func body(content: Content) -> some View {
        let source = Binding<GetawaySource?>(
            get: { app.getawaysSource },
            set: { app.getawaysSource = $0 })
        content
            .sheet(item: source, onDismiss: { app.presentDeferredPaywall() }) { opened in
                NavigationStack {
                    GetawaysScreen(source: opened) { app.getawaysSource = nil }
                }
                .frame(minWidth: sized ? 360 : nil, minHeight: sized ? 480 : nil)
            }
    }
}
