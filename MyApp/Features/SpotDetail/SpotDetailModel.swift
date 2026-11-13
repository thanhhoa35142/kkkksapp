import Foundation
import Observation

@MainActor @Observable
final class SpotDetailModel {
    enum Phase: Equatable { case loading, loaded, failed(String) }

    private(set) var detail: SpotDetail?
    private(set) var forecast: [ForecastPoint] = []
    private(set) var phase: Phase = .loading

    /// Hour chosen on the chart; nil = follow the app-wide "When".
    var selectedHour: Date?

    func load(id: UUID) async {
        if detail == nil { phase = .loading }
        async let detailCall = AppConfig.apiClient.spot(id: id)
        async let forecastCall = AppConfig.apiClient.forecast(spotID: id)
        do {
            detail = try await detailCall
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            phase = detail == nil ? .failed(error.localizedDescription) : .loaded
        }
        do {
            forecast = try await forecastCall
        } catch {
            Log.api.error("forecast failed: \(error.localizedDescription)")
        }
    }

    func point(at hour: Date) -> ForecastPoint? {
        forecast.first { abs($0.tsHour.timeIntervalSince(hour)) < 60 }
    }

    /// Forecast grouped into the spot's local days (max 7).
    func days(in timeZone: TimeZone) -> [Date] {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        var seen: [Date] = []
        for p in forecast {
            let day = calendar.startOfDay(for: p.tsHour)
            if seen.last != day { seen.append(day) }
        }
        return Array(seen.prefix(7))
    }

    func points(on day: Date, in timeZone: TimeZone) -> [ForecastPoint] {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return forecast.filter { calendar.isDate($0.tsHour, inSameDayAs: day) }
    }
}
