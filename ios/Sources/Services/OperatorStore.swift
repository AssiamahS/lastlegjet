import Foundation
import Combine

/// Operator tab data: profile, open requests + quoting, empty legs, fleet, trips, payouts.
/// Live against `/operator/*`; falls back to `PreviewWorld` in sample mode, offline, for routes the
/// server doesn't have yet, or when the signed-in account isn't an operator (demo).
@MainActor
final class OperatorStore: ObservableObject {
    @Published private(set) var profile: OperatorProfile?
    @Published private(set) var requests: [TripRequest] = []
    @Published private(set) var quotes: [OperatorQuote] = []
    @Published private(set) var flights: [Flight] = []
    @Published private(set) var aircraft: [Aircraft] = []
    @Published private(set) var bookings: [Booking] = []
    @Published private(set) var payouts: PayoutSummary?
    @Published private(set) var trackingByBooking: [String: Tracking] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    /// Sections currently served from preview data, with the reason for the banner.
    @Published private(set) var previewReason: String?

    private let api = APIClient.shared
    private let mode = AppMode.shared
    private let world = PreviewWorld.shared
    /// Whole tab on preview (sample mode / offline / not an operator account).
    private var allPreview = false
    /// Uber-mode routes missing on the server: requests + quotes + status come from preview.
    private var uberPreview = false

    var usingPreview: Bool { allPreview || uberPreview }

    // MARK: Loading

    func load(user: User?) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if mode.isSample {
            allPreview = true
            previewReason = mode.forced ? "Sample data — on this device" : "Sample data — server unreachable"
        } else if user?.isOperator != true {
            allPreview = true
            previewReason = "Demo — sign in as an operator (Account) for live data"
        } else {
            allPreview = false
            previewReason = nil
        }
        if allPreview {
            loadPreviewAll()
            return
        }

        async let profileTask: OperatorProfile? = fetch("/operator/me")
        async let flightsTask: [Flight]? = fetch("/operator/flights")
        async let aircraftTask: [Aircraft]? = fetch("/operator/aircraft")
        async let bookingsTask: [Booking]? = fetch("/operator/bookings")
        async let payoutsTask: PayoutSummary? = fetch("/operator/payouts")
        let (p, f, a, b, pay) = await (profileTask, flightsTask, aircraftTask, bookingsTask, payoutsTask)
        if mode.offline {
            allPreview = true
            previewReason = "Sample data — server unreachable"
            loadPreviewAll()
            return
        }
        profile = p
        flights = (f ?? []).sorted { $0.departsAt < $1.departsAt }
        aircraft = a ?? []
        bookings = b ?? []
        payouts = pay
        await loadUberMode()
    }

    /// Requests inbox + my quotes (`/operator/requests`, `/operator/quotes`).
    func loadUberMode() async {
        if allPreview {
            requests = world.operatorInbox()
            quotes = world.operatorQuotes()
            return
        }
        do {
            let page: ItemsEnvelope<TripRequest> = try await api.get("/operator/requests",
                                                                     query: [URLQueryItem(name: "status", value: "open")], auth: true)
            requests = page.items
            uberPreview = false
            if previewReason?.hasPrefix("Preview") == true { previewReason = nil }
            if let mine: ItemsEnvelope<OperatorQuote> = try? await api.get("/operator/quotes", auth: true) {
                quotes = mine.items
            }
        } catch let error as APIError where error.shouldUsePreview {
            uberPreview = true
            previewReason = "Preview — requests & quotes aren't live on this server yet"
            requests = world.operatorInbox()
            quotes = world.operatorQuotes()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadPreviewAll() {
        profile = world.profile
        flights = world.flights
        aircraft = world.aircraft
        bookings = world.bookings()
        payouts = world.payouts
        requests = world.operatorInbox()
        quotes = world.operatorQuotes()
    }

    private func fetch<T: Decodable>(_ path: String) async -> T? {
        do {
            return try await api.get(path, auth: true)
        } catch let error as APIError {
            if error.isUnreachable { mode.offline = true }
            if errorMessage == nil, !error.isUnreachable { errorMessage = error.localizedDescription }
            return nil
        } catch {
            return nil
        }
    }

    // MARK: Derived

    var openRequestCount: Int { requests.filter(\.isActive).count }

    /// Confirmed bookings departing today (local calendar), then any later confirmed ones.
    var todaysTrips: [Booking] {
        let calendar = Calendar.current
        return bookings.filter { b in
            guard b.isConfirmed, let f = b.flight else { return false }
            return calendar.isDateInToday(f.departsAt)
        }
    }

    var upcomingTrips: [Booking] {
        bookings.filter { $0.isConfirmed && ($0.flight?.departsAt ?? .distantPast) > Date().addingTimeInterval(-12 * 3600) }
            .sorted { ($0.flight?.departsAt ?? .distantPast) < ($1.flight?.departsAt ?? .distantPast) }
    }

    var canEdit: Bool { allPreview || profile != nil }

    // MARK: Actions

    func sendQuote(requestId: String, body: CreateQuoteBody) async throws {
        if allPreview || uberPreview {
            _ = try world.sendQuote(requestId: requestId, body: body)
        } else {
            let _: Quote = try await api.post("/operator/requests/\(requestId)/quotes", body: body, auth: true)
        }
        await loadUberMode()
    }

    func withdraw(quoteId: String) async throws {
        if allPreview || uberPreview || quoteId.hasPrefix("local_") || quoteId.hasPrefix("sample_") {
            _ = try world.withdrawQuote(id: quoteId)
        } else {
            let _: Quote = try await api.post("/operator/quotes/\(quoteId)/withdraw", auth: true)
        }
        await loadUberMode()
    }

    func postLeg(_ body: CreateFlightBody) async throws {
        if allPreview {
            _ = try world.addFlight(body)
            flights = world.flights
            return
        }
        let flight: Flight = try await api.post("/operator/flights", body: body, auth: true)
        flights = (flights + [flight]).sorted { $0.departsAt < $1.departsAt }
    }

    func addAircraft(_ body: CreateAircraftBody) async throws {
        if allPreview {
            _ = world.addAircraft(body)
            aircraft = world.aircraft
            return
        }
        let plane: Aircraft = try await api.post("/operator/aircraft", body: body, auth: true)
        aircraft.append(plane)
    }

    func loadTracking(for booking: Booking) async {
        if let t = await tracking(for: booking) {
            trackingByBooking[booking.id] = t
        }
    }

    private func tracking(for booking: Booking) async -> Tracking? {
        if allPreview || uberPreview || booking.id.hasPrefix("local_") || booking.id.hasPrefix("sample_") {
            return world.tracking(for: booking)
        }
        do {
            return try await api.get("/bookings/\(booking.id)/track", auth: true)
        } catch let error as APIError where error.shouldUsePreview {
            uberPreview = true
            return world.tracking(for: booking)
        } catch {
            return nil
        }
    }

    /// `PATCH /operator/bookings/:id/status` with the phone's position when available.
    func advance(booking: Booking, to status: TripStatus, location: (lat: Double, lng: Double)?,
                 etaMinutes: Int?, note: String?) async throws {
        let body = StatusUpdateBody(status: status, lat: location?.lat, lng: location?.lng,
                                    etaMinutes: etaMinutes, note: note)
        if allPreview || uberPreview || booking.id.hasPrefix("local_") || booking.id.hasPrefix("sample_") {
            if let t = world.updateStatus(booking: booking, body: body) { trackingByBooking[booking.id] = t }
            return
        }
        do {
            let t: Tracking = try await api.patch("/operator/bookings/\(booking.id)/status", body: body, auth: true)
            trackingByBooking[booking.id] = t
        } catch let error as APIError where error.isRouteMissing {
            uberPreview = true
            if let t = world.updateStatus(booking: booking, body: body) { trackingByBooking[booking.id] = t }
        }
    }
}
