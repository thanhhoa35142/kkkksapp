import MapKit
import SwiftUI

/// Toolbar menu: which hour every screen shows (UI_SPEC S6).
struct WhenMenu: View {
    @Environment(AppState.self) private var app
    @State private var showPicker = false

    var body: some View {
        Menu {
            ForEach(WhenPreset.allCases) { preset in
                let selection = preset.selection()
                Button {
                    app.select(when: selection)
                    app.track("when_changed", ["preset": .string("\(preset)")])
                } label: {
                    if selection.needsPlus() && !app.isPlus {
                        Label(preset.title, systemImage: "lock.fill")
                    } else {
                        Text(preset.title)
                    }
                }
            }
            Divider()
            Button("Choose a Time…") { showPicker = true }
        } label: {
            Text(app.when.label)
                .monospacedDigit()
        }
        .accessibilityLabel(Text("Time: \(app.when.label)"))
        .sheet(isPresented: $showPicker) {
            WhenPickerSheet()
        }
    }
}

/// "Choose a Time…" — day (7 days) + hour (UI_SPEC S6).
struct WhenPickerSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var hour = Calendar.current.component(.hour, from: .now)

    private var range: ClosedRange<Date> {
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        return start...end
    }

    private var selection: WhenSelection {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? .now
        return date <= Date.now.startOfHour ? .now : .at(date)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Day", selection: $day, in: range, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                Picker("Hour", selection: $hour) {
                    ForEach(0..<24, id: \.self) { h in
                        let date = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: day) ?? day
                        Text(Format.hour(date)).tag(h)
                    }
                }
                if selection.needsPlus() && !app.isPlus {
                    Section {
                        Label("Hourly scores after tomorrow need Plus", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Choose a Time")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                        app.select(when: selection)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// Toolbar menu: where Best Now looks.
struct PlaceMenu: View {
    @Binding var showCityPicker: Bool
    @Environment(AppState.self) private var app

    var body: some View {
        Menu {
            Button("Current Location", systemImage: "location") {
                Task {
                    _ = await app.location.requestAuthorization()
                    if app.location.isAuthorized { app.setPlace(.currentLocation) }
                }
            }
            .disabled(app.location.isDenied)
            Button("Choose a City…") { showCityPicker = true }
        } label: {
            Text(app.place?.title ?? String(localized: "Choose Place"))
                .lineLimit(1)
        }
    }
}

/// City packs grouped by country (UI_SPEC S12 / onboarding "Choose a City").
struct CityPickerList: View {
    var onPicked: () -> Void

    @Environment(AppState.self) private var app
    @State private var query = ""

    private var grouped: [(country: String, packs: [CityPack])] {
        let filtered = app.packs.filter {
            query.isEmpty
                || $0.name.localizedCaseInsensitiveContains(query)
                || $0.countryName.localizedCaseInsensitiveContains(query)
        }
        let byCountry = Dictionary(grouping: filtered, by: \.countryName)
        return byCountry.keys.sorted().map { country in
            let packs = (byCountry[country] ?? []).sorted { lhs, rhs in lhs.name < rhs.name }
            return (country: country, packs: packs)
        }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.country) { group in
                Section(group.country) {
                    ForEach(group.packs) { pack in
                        Button {
                            guard let c = pack.coordinate else { return }
                            app.setPlace(.city(slug: pack.slug, name: pack.name,
                                               latitude: c.latitude, longitude: c.longitude))
                            app.track("city_chosen", ["slug": .string(pack.slug)])
                            onPicked()
                        } label: {
                            LabeledContent(pack.name) {
                                Text("\(pack.activeSpots) spots")
                                    .monospacedDigit()
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
        }
        .groupedList()
        // Loading / failed: full-screen system states over the empty list.
        .overlay {
            if app.packs.isEmpty {
                if let error = app.packsError {
                    ContentUnavailableView {
                        Label("Can't load cities", systemImage: "wifi.slash")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") { Task { await app.loadPacksIfNeeded() } }
                    }
                } else {
                    ProgressView()
                }
            } else if grouped.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Choose a City")
        .inlineTitle()
        .searchable(text: $query, prompt: "City or country")
        .task { await app.loadPacksIfNeeded() }
    }
}

/// Opens Apple Maps directions (F4).
enum Directions {
    static func open(name: String, coordinate: CLLocationCoordinate2D) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}
