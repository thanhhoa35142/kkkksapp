#if os(iOS)
import EventKit
import EventKitUI
import SwiftUI

/// "Add to Calendar" for a plan window: Apple's own event editor,
/// pre-filled. On iOS 17 `EKEventEditViewController` runs out of process
/// and needs no calendar permission (the user saves or cancels in the
/// system UI), so the app never asks for calendar access.
struct CalendarEventSheet: UIViewControllerRepresentable {
    let title: String
    let start: Date
    let end: Date
    let timeZone: TimeZone
    let url: URL?
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.timeZone = timeZone
        event.url = url
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func eventEditViewController(_ controller: EKEventEditViewController,
                                     didCompleteWith action: EKEventEditViewAction) {
            onFinish()
        }
    }
}
#endif
