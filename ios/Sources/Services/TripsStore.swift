import Foundation
import Combine

/// Customer side of "Uber mode": trip requests, incoming quotes, accepting, and live tracking.
/// Falls back to `PreviewWorld` in sample mode, offline, or when the server lacks the routes.
@MainActor
final class TripsStore: ObservableObject {
    @Published private(set) var requests: [TripRequest] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    /// True while the data comes from `PreviewWorld` instead of the API.
    @Published private(set) var usingPreview = false
    /// Why preview is on (shown in the banner).
    @Published private(set) var previewReason: String?

    private let api = APIClient.shared
    private let mode = AppMode.shared
    private let world = PreviewWorld.shared
    private var seenQuoteIds: Set<String> = []
    private var primed = false

    private func usePreview(_ reason: String) {
        usingPreview = true
        previewReason = reason
    }

    private func useLive() {
        usingPreview = false
        previewReason = nil
    }

    /// Preview whenever sample mode is on or the user isn't signed in (requests need an account).
    private func previewFirst(signedIn: Bool) -> Bool {
        if mode.isSample {
            usePreview(mode.forced ? "Sample data — on this device" : "Sample data — server unreachable")
            return true
        }
        if !signedIn {
            usePreview("Preview — sign in to send real requests")
            return true
        }
        return false
    }

    private func handlePreviewFallback(_ error: Error) -> Bool {
        guard let apiError = error as? APIError, apiError.shouldUsePreview else { return false }
        if apiError.isUnreachable {
            mode.offline = true
            usePreview("Sample data — server unreachable")
        } else {
            usePreview("Preview — trip requests aren't live on this server yet")
        }
        return true
    }

    // MARK: Requests

    func load(signedIn: Bool) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        if previewFirst(signedIn: signedIn) {
            apply(world.customerRequests())
            return
        }
        do {
            let page: ItemsEnvelope<TripRequest> = try await api.get("/trip-requests", auth: true)
            useLive()
            apply(page.items)
        } catch {
            if handlePreviewFallback(error) {
                apply(world.customerRequests())
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func create(_ body: CreateTripRequestBody, signedIn: Bool) async throws -> TripRequest {
        if previewFirst(signedIn: signedIn) {
            let request = try world.createRequest(body)
            apply(world.customerRequests())
            return request
        }
        do {
            let request: TripRequest = try await api.post("/trip-requests", body: body, auth: true)
            useLive()
            upsert(request)
            return request
        } catch {
            guard handlePreviewFallback(error) else { throw error }
            let request = try world.createRequest(body)
            apply(world.customerRequests())
            return request
        }
    }

    func refresh(id: String) async throws -> TripRequest {
        if usingPreview || isPreviewId(id) {
            guard let request = world.request(id: id) else {
                throw APIError.server(statusCode: 404, message: "Trip request not found")
            }
            upsert(request)
            return request
        }
        do {
            let request: TripRequest = try await api.get("/trip-requests/\(id)", auth: true)
            upsert(request)
            return request
        } catch {
            guard handlePreviewFallback(error), let request = world.request(id: id) else { throw error }
            upsert(request)
            return request
        }
    }

    func cancel(id: String) async throws -> TripRequest {
        if usingPreview || isPreviewId(id) {
            guard let request = world.cancelRequest(id: id) else {
                throw APIError.server(statusCode: 404, message: "Trip request not found")
            }
            upsert(request)
            return request
        }
        let request: TripRequest = try await api.post("/trip-requests/\(id)/cancel", auth: true)
        upsert(request)
        return request
    }

    /// Accepts a quote and returns the HELD booking, which goes through the normal payment flow.
    func accept(request: TripRequest, quote: Quote, bookings: BookingsStore) async throws -> Booking {
        if usingPreview || isPreviewId(request.id) {
            let (_, flight, _) = try world.flightForAccepting(requestId: request.id, quoteId: quote.id)
            let booking = bookings.createLocalHold(flight: flight, passengers: request.passengers)
            if let updated = world.recordAcceptance(requestId: request.id, quoteId: quote.id, booking: booking) {
                upsert(updated)
            }
            return booking
        }
        let response: AcceptQuoteResponse = try await api.post(
            "/trip-requests/\(request.id)/quotes/\(quote.id)/accept", auth: true)
        upsert(response.tripRequest)
        bookings.adopt(response.booking)
        return response.booking
    }

    // MARK: Tracking

    /// `GET /bookings/:id/track`; local/sample bookings and servers without the route use the simulation.
    func track(_ booking: Booking) async throws -> Tracking? {
        if mode.isSample || booking.id.hasPrefix("local_") || booking.id.hasPrefix("sample_") {
            return world.tracking(for: booking)
        }
        do {
            let tracking: Tracking = try await api.get("/bookings/\(booking.id)/track", auth: true)
            return tracking
        } catch let error as APIError where error.shouldUsePreview {
            return world.tracking(for: booking)
        }
    }

    /// Bookings that only exist in the preview world (the seeded in-flight charter), shown in Trips.
    func previewBookings(excluding ids: Set<String>) -> [Booking] {
        guard usingPreview else { return [] }
        return world.bookings().filter { !ids.contains($0.id) }
    }

    // MARK: Helpers

    private func isPreviewId(_ id: String) -> Bool {
        id.hasPrefix("local_") || id.hasPrefix("sample_")
    }

    private func apply(_ items: [TripRequest]) {
        requests = items.sorted { $0.createdAt > $1.createdAt }
        announceNewQuotes()
    }

    private func upsert(_ request: TripRequest) {
        if let i = requests.firstIndex(where: { $0.id == request.id }) {
            requests[i] = request
        } else {
            requests.insert(request, at: 0)
        }
        announceNewQuotes()
    }

    /// Local notification for each quote that shows up after the first load (Uber-style "driver found").
    private func announceNewQuotes() {
        let live = requests.filter(\.isActive).flatMap { r in r.liveQuotes().map { (r, $0) } }
        defer {
            seenQuoteIds.formUnion(live.map { $0.1.id })
            primed = true
        }
        guard primed else { return }
        for (request, quote) in live where !seenQuoteIds.contains(quote.id) {
            PushRegistrar.shared.notifyLocally(
                title: "New quote: \(quote.priceText)",
                body: "\(quote.operatorInfo.displayName) · \(quote.aircraft.model) · \(request.routeCode)")
        }
    }
}
