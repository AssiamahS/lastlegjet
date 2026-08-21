import Foundation
import Combine

@MainActor
final class FlightsStore: ObservableObject {
    @Published private(set) var flights: [Flight] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var usingSampleData = false

    private let api = APIClient.shared
    private let mode = AppMode.shared

    func search(_ query: FlightQuery = FlightQuery()) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if mode.forced {
            applySample(query)
            return
        }
        do {
            let page: FlightPage = try await api.get("/flights", query: query.queryItems)
            flights = page.items.sorted { $0.departsAt < $1.departsAt }
            usingSampleData = false
            mode.offline = false
        } catch let error as APIError where error.isUnreachable {
            mode.offline = true
            applySample(query)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func detail(for id: String) async throws -> FlightDetail {
        if mode.isSample {
            if let detail = SampleData.flightDetail(id: id) { return detail }
            throw APIError.server(statusCode: 404, message: "Flight not found")
        }
        do {
            return try await api.get("/flights/\(id)")
        } catch let error as APIError where error.isUnreachable {
            mode.offline = true
            if let detail = SampleData.flightDetail(id: id) { return detail }
            throw error
        }
    }

    func airports(matching query: String) async -> [Airport] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        if mode.isSample { return SampleData.airports(matching: q) }
        do {
            let results: [Airport] = try await api.get("/airports", query: [URLQueryItem(name: "q", value: q)])
            return results
        } catch {
            return SampleData.airports(matching: q)
        }
    }

    /// Local seat decrement so sample-mode bookings are reflected in the list.
    func applyLocalHold(flightId: String, passengers: Int) {
        flights = flights.map { flight in
            guard flight.id == flightId else { return flight }
            return flight.withSeatsAvailable(max(0, flight.seatsAvailable - passengers))
        }
    }

    private func applySample(_ query: FlightQuery) {
        flights = SampleData.flights()
            .filter { query.matches($0) }
            .sorted { $0.departsAt < $1.departsAt }
        usingSampleData = true
    }
}
