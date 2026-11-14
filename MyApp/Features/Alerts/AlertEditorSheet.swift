import SwiftUI

/// S10 · Alert editor — "tell me when this spot (or any spot within N km of
/// this place) scores ≥ N in my window". Area rules send a coarse point; the
/// server turns it into an H3 cell and picks the best spot when it fires.
/// Over the Free limit the paywall is pushed inside this sheet rather than
/// stacking a third sheet (UI_SPEC §9).
struct AlertEditorSheet: View {
    /// nil = area rule.
    let spotID: UUID?
    /// Spot name, or the place name for an area rule.
    let spotName: String
    let timeZone: TimeZone
    /// nil = create.
    var existing: AlertRule?
    /// New area rule: centre of the area (already coarse).
    var areaCenter: AreaPoint?
    /// Called after a successful save — the caller confirms it in place
    /// (M5: Spot Detail bounces its bell), since this sheet closes.
    var onSaved: (() -> Void)?

    static let radiusOptions = [1_000, 3_000, 5_000, 10_000]

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var minScore = 75
    @State private var daysPreset = DaysPreset.weekends
    @State private var customMask = DaysMask.weekends
    @State private var start = LocalTime.date(from: "10:00")
    @State private var end = LocalTime.date(from: "18:00")
    @State private var enabled = true
    @State private var isSaving = false
    @State private var error: String?
    @State private var showPaywall = false
    @State private var confirmDiscard = false
    @State private var initial: Snapshot?
    @State private var saved = 0
    @State private var radiusM = 3_000

    private var isArea: Bool { spotID == nil }

    private enum DaysPreset: Hashable, CaseIterable {
        case everyDay, weekdays, weekends, custom
        var title: String {
            switch self {
            case .everyDay: String(localized: "Every day")
            case .weekdays: String(localized: "Weekdays")
            case .weekends: String(localized: "Weekends")
            case .custom: String(localized: "Custom")
            }
        }
        var mask: Int? {
            switch self {
            case .everyDay: DaysMask.everyDay
            case .weekdays: DaysMask.weekdays
            case .weekends: DaysMask.weekends
            case .custom: nil
            }
        }
    }

    private struct Snapshot: Equatable {
        let minScore: Int, mask: Int, start: String, end: String, enabled: Bool, radiusM: Int
    }

    private var mask: Int { daysPreset.mask ?? customMask }

    private var snapshot: Snapshot {
        Snapshot(minScore: minScore, mask: mask, start: LocalTime.text(from: start),
                 end: LocalTime.text(from: end), enabled: enabled, radiusM: isArea ? radiusM : 0)
    }

    private var isDirty: Bool { initial != nil && snapshot != initial }

    var body: some View {
        NavigationStack {
            Form {
                if isArea {
                    Section {
                        LabeledContent("Around", value: spotName)
                        Picker("Within", selection: $radiusM) {
                            ForEach(Self.radiusOptions, id: \.self) { meters in
                                Text(Format.distance(meters: Double(meters))).tag(meters)
                            }
                        }
                    } footer: {
                        Text("You'll hear about the best spot in this area when it reaches your score.")
                    }
                } else {
                    Section {
                        LabeledContent("Spot", value: spotName)
                    }
                }

                Section {
                    Stepper(value: $minScore, in: 40...95, step: 5) {
                        LabeledContent("Score at least") {
                            Text("\(minScore)").monospacedDigit()
                        }
                    }
                } footer: {
                    Text("\(ScoreTier(score: minScore).label) or better.")
                }

                Section("Days") {
                    Picker("Days", selection: $daysPreset) {
                        ForEach(DaysPreset.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if daysPreset == .custom {
                        ForEach(DaysMask.orderedIndices, id: \.self) { index in
                            Toggle(Calendar.current.weekdaySymbols[index], isOn: dayBinding(index))
                        }
                    }
                }

                Section {
                    DatePicker("From", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: $end, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Between")
                } footer: {
                    let zone = timeZone.localizedName(for: .shortGeneric, locale: .current) ?? timeZone.identifier
                    if isArea {
                        Text("Times are local to this area (\(zone)).")
                    } else {
                        Text("Times are local to the spot (\(zone)).")
                    }
                }

                if existing != nil {
                    Section {
                        Toggle("Enabled", isOn: $enabled)
                    }
                    Section {
                        Button("Delete Alert", role: .destructive) {
                            Task {
                                if let existing { await app.alerts.delete(existing) }
                                dismiss()
                            }
                        }
                    }
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existing == nil ? "New Alert" : "Edit Alert")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty { confirmDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(isSaving || mask == 0)
                }
            }
            .confirmationDialog("Discard changes?", isPresented: $confirmDiscard) {
                Button("Discard Changes", role: .destructive) { dismiss() }
            }
            .navigationDestination(isPresented: $showPaywall) {
                PaywallSheet(reason: .alerts)
            }
            .sensoryFeedback(.success, trigger: saved)
        }
        .interactiveDismissDisabled(isDirty)
        .onAppear(perform: loadExisting)
    }

    private func dayBinding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { DaysMask.contains(customMask, weekday: index) },
            set: { isOn in
                if isOn { customMask |= (1 << index) } else { customMask &= ~(1 << index) }
            }
        )
    }

    private func loadExisting() {
        guard initial == nil else { return }
        if let rule = existing {
            minScore = rule.minScore
            customMask = rule.daysMask
            daysPreset = DaysPreset.allCases.first { $0.mask == rule.daysMask } ?? .custom
            start = LocalTime.date(from: rule.startLocal)
            end = LocalTime.date(from: rule.endLocal)
            enabled = rule.enabled
            if let r = rule.radiusM { radiusM = r }
        }
        initial = snapshot
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        error = nil
        // Editing an area rule keeps its cell; a new one sends the point.
        let request = AlertRuleRequest(
            deviceId: DeviceIdentity.deviceID, spotId: spotID,
            h3Cell: isArea ? existing?.h3Cell : nil,
            area: isArea && existing?.h3Cell == nil ? (existing?.areaCenter ?? areaCenter) : nil,
            radiusM: isArea ? radiusM : nil,
            minScore: minScore, daysMask: mask,
            startLocal: LocalTime.text(from: start), endLocal: LocalTime.text(from: end),
            tz: existing?.tz ?? timeZone.identifier, enabled: enabled)
        switch await app.alerts.save(request, id: existing?.id, spotName: spotName) {
        case .saved:
            app.track(existing == nil ? "alert_created" : "alert_updated",
                      ["target": .string(isArea ? "area" : "spot")])
            saved += 1
            onSaved?()
            dismiss()
        case .needsPlus:
            showPaywall = true
        case .failed(let message):
            error = message
        }
    }
}

extension AlertEditorSheet {
    /// Edit an existing rule (spot or area).
    @MainActor
    init(editing rule: AlertRule, app: AppState) {
        self.init(spotID: rule.spotId,
                  spotName: app.alerts.displayName(for: rule, summaries: app.summaries),
                  timeZone: TimeZone(identifier: rule.tz) ?? .current,
                  existing: rule,
                  areaCenter: rule.areaCenter)
    }
}

/// Saved › Alerts row: "Vondelpark" / "Weekends · 10:00 AM–6:00 PM · 75+".
/// Two separate controls, the native way: the text is a button that opens
/// the editor (with a chevron as the affordance), the switch pauses or
/// resumes the alert. No row-wide tap gesture fighting the toggle.
struct AlertRow: View {
    let rule: AlertRule
    let name: String
    var onEdit: () -> Void = {}

    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.headline)
                            .foregroundStyle(Color.primary)
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Edit alert"))

            Toggle(isOn: Binding(
                get: { rule.enabled },
                set: { value in Task { await app.alerts.setEnabled(rule, value) } }
            )) {
                Text(name)
            }
            .labelsHidden()
        }
    }

    private var summary: String {
        var parts: [String] = []
        if rule.isArea, let r = rule.radiusM {
            parts.append(String(localized: "Within \(Format.distance(meters: Double(r)))"))
        }
        parts.append(DaysMask.label(rule.daysMask))
        parts.append("\(LocalTime.display(rule.startLocal))–\(LocalTime.display(rule.endLocal))")
        parts.append("\(rule.minScore)+")
        return parts.joined(separator: " · ")
    }
}
