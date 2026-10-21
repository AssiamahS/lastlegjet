import Foundation

/// Loads the JSON captured from the live API (`Resources/SampleData`) for offline / demo mode.
enum SampleData {
    static func flights() -> [Flight] {
        guard let page: FlightPage = load("flights") else { return [] }
        return page.items
    }

    static func flightDetail(id: String) -> FlightDetail? {
        if let detail: FlightDetail = load("flight-detail-\(id)") {
            return detail
        }
        guard let flight = flights().first(where: { $0.id == id }) else { return nil }
        return FlightDetail(flight: flight, similar: [])
    }

    static func airports() -> [Airport] {
        load("airports") ?? []
    }

    static func airports(matching query: String) -> [Airport] {
        let all = airports()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return Array(all.filter { $0.matches(q) }.prefix(20))
    }

    /// Demo customer used when booking locally without a server.
    static let guestUser = User(id: "sample_user", email: "guest@lastlegjet.dev",
                                firstName: "Guest", lastName: "Traveller", role: "CUSTOMER",
                                emailVerifiedAt: nil, mfaEnabled: false)

    /// `GET /payments/methods` as captured from the API in mock mode; all four rails enabled.
    static func paymentMethods() -> [PaymentMethodInfo] {
        if let bundled: [PaymentMethodInfo] = load("payment-methods"), !bundled.isEmpty {
            return bundled
        }
        return [
            .mock(.card, note: "Sandbox: no charge is made"),
            .mock(.klarna, note: "Sandbox: no charge is made"),
            .mock(.paypal, note: "Sandbox: approval page is simulated"),
            .mock(.crypto, note: "Sandbox: address is simulated, rate locked 15 min"),
        ]
    }

    /// Closest bundled airport (the same 20 the API knows) to a coordinate.
    static func nearestAirport(lat: Double, lng: Double) -> Airport? {
        airports().min {
            Geo.distanceKm(lat1: lat, lng1: lng, lat2: $0.lat, lng2: $0.lng)
                < Geo.distanceKm(lat1: lat, lng1: lng, lat2: $1.lat, lng2: $1.lng)
        }
    }

    // MARK: Uber mode (dates rebased so the bundled scenario is always "now")

    /// Every ISO date in the Uber-mode sample files is written relative to this instant;
    /// `loadRebased` shifts them by (launch time − anchor).
    static let anchor: Date = ISO8601DateFormatter().date(from: "2026-10-21T18:00:00Z") ?? Date()

    static func tripRequests() -> [TripRequest] {
        (loadRebased("trip-requests") as ItemsEnvelope<TripRequest>?)?.items ?? []
    }

    static func tripBookings() -> [Booking] { loadRebased("trip-bookings") ?? [] }
    static func tracking(bookingId: String) -> Tracking? { loadRebased("tracking-\(bookingId)") }
    static func operatorProfile() -> OperatorProfile? { loadRebased("operator-me") }
    static func operatorAircraft() -> [Aircraft] { loadRebased("operator-aircraft") ?? [] }
    static func operatorFlights() -> [Flight] { loadRebased("operator-flights") ?? [] }
    static func operatorBookings() -> [Booking] { loadRebased("operator-bookings") ?? [] }
    static func operatorPayouts() -> PayoutSummary? { loadRebased("operator-payouts") }

    static func operatorRequests() -> [TripRequest] {
        (loadRebased("operator-requests") as ItemsEnvelope<TripRequest>?)?.items ?? []
    }

    static func operatorQuotes() -> [OperatorQuote] {
        (loadRebased("operator-quotes") as ItemsEnvelope<OperatorQuote>?)?.items ?? []
    }

    static func loadRebased<T: Decodable>(_ name: String, now: Date = Date()) -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return decodeRebased(data, now: now)
    }

    /// Shifts every ISO-8601 string in `data` by (now − anchor), then decodes.
    static func decodeRebased<T: Decodable>(_ data: Data, now: Date = Date()) -> T? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        let shifted = rebase(json, by: now.timeIntervalSince(anchor))
        guard let out = try? JSONSerialization.data(withJSONObject: shifted, options: [.fragmentsAllowed]) else { return nil }
        return try? APIClient.decoder.decode(T.self, from: out)
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func rebase(_ value: Any, by delta: TimeInterval) -> Any {
        if let dict = value as? [String: Any] {
            return dict.mapValues { rebase($0, by: delta) }
        }
        if let array = value as? [Any] {
            return array.map { rebase($0, by: delta) }
        }
        if let string = value as? String, string.count >= 20, string.hasSuffix("Z"),
           string.dropFirst(4).first == "-", let date = isoFractional.date(from: string) {
            return isoFractional.string(from: date.addingTimeInterval(delta))
        }
        return value
    }

    private static func load<T: Decodable>(_ name: String) -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? APIClient.decoder.decode(T.self, from: data)
    }
}
