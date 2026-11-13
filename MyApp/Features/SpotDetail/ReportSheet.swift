import SwiftUI

/// S9 · "Is this spot correct?" — preset answers only, no free text (spec D5).
struct ReportSheet: View {
    let spotID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var isSending = false
    @State private var error: String?
    @State private var sent = 0

    private enum Kind: String, CaseIterable, Identifiable {
        case confirm, missing, closed
        var id: String { rawValue }
        var title: String {
            switch self {
            case .confirm: String(localized: "It's still here")
            case .missing: String(localized: "It's gone")
            case .closed: String(localized: "It's closed")
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Kind.allCases) { kind in
                        Button(kind.title) { Task { await send(kind) } }
                            .disabled(isSending)
                    }
                } header: {
                    Text("Is this spot correct?")
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text("Reports are anonymous and reviewed before anything changes.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Report")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sensoryFeedback(.success, trigger: sent)
        }
        .presentationDetents([.medium])
    }

    private func send(_ kind: Kind) async {
        isSending = true
        defer { isSending = false }
        do {
            try await AppConfig.apiClient.submitSpotReport(
                spotID: spotID, deviceID: DeviceIdentity.deviceID, type: kind.rawValue)
            sent += 1
            dismiss()
        } catch let apiError as APIError where apiError.code == "rate_limited" {
            error = String(localized: "You've sent a lot of reports today. Try again tomorrow.")
        } catch {
            self.error = error.localizedDescription
        }
    }
}
