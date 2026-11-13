import SwiftUI

/// Toolbar button — outline icon, `.fill` when any filter is on (UI_SPEC S8).
struct FilterButton: View {
    @Environment(AppState.self) private var app
    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            Label("Filters", systemImage: app.filters.isActive
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
        .accessibilityValue(app.filters.isActive
                            ? Text("\(app.filters.activeCount) active")
                            : Text("Off"))
        #if os(iOS)
        .sheet(isPresented: $showSheet) { FiltersSheet() }
        #else
        .popover(isPresented: $showSheet, arrowEdge: .bottom) {
            FiltersSheet().frame(width: 360, height: 520)
        }
        #endif
    }
}

/// S8 · Filters — kind, must-have amenities, minimum score.
/// Edits a draft; Done applies it (one reload instead of one per toggle).
struct FiltersSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft = SpotFilters()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(SpotFilters.allKinds, id: \.self) { kind in
                        Toggle(KindStyle.label(kind), isOn: binding(for: kind, in: \.kinds))
                    }
                } header: {
                    Text("Kind")
                } footer: {
                    Text("None selected shows every kind.")
                }

                Section("Must have") {
                    ForEach(SpotFilters.filterableAmenities, id: \.self) { amenity in
                        Toggle(AmenityStyle.label(amenity), isOn: binding(for: amenity, in: \.amenities))
                    }
                }

                Section("Minimum score") {
                    Picker("Minimum score", selection: $draft.minScore) {
                        Text("Any").tag(Int?.none)
                        ForEach(SpotFilters.minScoreOptions, id: \.self) { value in
                            Text("\(value)+").tag(Int?.some(value))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Filters")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { draft = SpotFilters() }
                        .disabled(!draft.isActive)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if draft != app.filters {
                            app.setFilters(draft)
                            app.track("filters_applied", ["count": .number(Double(draft.activeCount))])
                        }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { draft = app.filters }
    }

    private func binding(for value: String, in keyPath: WritableKeyPath<SpotFilters, Set<String>>) -> Binding<Bool> {
        Binding(
            get: { draft[keyPath: keyPath].contains(value) },
            set: { isOn in
                if isOn { draft[keyPath: keyPath].insert(value) }
                else { draft[keyPath: keyPath].remove(value) }
            }
        )
    }
}
