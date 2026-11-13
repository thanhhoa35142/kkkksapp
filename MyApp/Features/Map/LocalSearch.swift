import MapKit
import Observation

/// Place search for the map (F3) — MKLocalSearchCompleter suggestions,
/// resolved to a coordinate with MKLocalSearch on tap.
@MainActor @Observable
final class LocalSearch {
    struct Result: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        fileprivate let completion: MKLocalSearchCompletion
    }

    var query = ""
    private(set) var results: [Result] = []

    /// Call when `query` changes (from the view's onChange).
    func update() {
        if query.isEmpty { results = [] }
        completer.queryFragment = query
    }

    private let completer = MKLocalSearchCompleter()
    private let delegate = Delegate()

    init() {
        completer.resultTypes = [.address, .pointOfInterest]
        completer.delegate = delegate
        delegate.onResults = { [weak self] completions in
            MainActor.assumeIsolated {
                self?.results = completions.prefix(8).map {
                    Result(title: $0.title, subtitle: $0.subtitle, completion: $0)
                }
            }
        }
    }

    func resolve(_ result: Result) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request(completion: result.completion)
        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.first?.placemark.coordinate
        } catch {
            Log.geo.error("local search failed: \(error.localizedDescription)")
            return nil
        }
    }

    private final class Delegate: NSObject, MKLocalSearchCompleterDelegate {
        var onResults: (([MKLocalSearchCompletion]) -> Void)?

        func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
            onResults?(completer.results)
        }

        func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
            onResults?([])
        }
    }
}
