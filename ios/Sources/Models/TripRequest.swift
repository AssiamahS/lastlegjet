import Foundation

// "Uber mode" types from API_CONTRACT.md: trip requests, quotes, live tracking, devices.

enum TripRequestStatus: String, CaseIterable {
    case open = "OPEN"
    case quoted = "QUOTED"
    case accepted = "ACCEPTED"
    case cancelled = "CANCELLED"
    case expired = "EXPIRED"

    var label: String {
        switch self {
        case .open: return "Finding operators"
        case .quoted: return "Quotes in"
        case .accepted: return "Booked"
        case .cancelled: return "Cancelled"
        case .expired: return "Expired"
        }
    }
}

enum QuoteStatus: String {
    case pending = "PENDING"
    case accepted = "ACCEPTED"
    case declined = "DECLINED"
    case expired = "EXPIRED"
    case withdrawn = "WITHDRAWN"

    var label: String { rawValue.capitalized }
}

struct QuoteOperator: Codable, Hashable {
    let id: String
    let displayName: String
    let verificationStatus: String?

    var isVerified: Bool { verificationStatus == "VERIFIED" }
}

struct QuoteAircraft: Codable, Hashable {
    let id: String
    let model: String
    let category: String
    let seats: Int
    let images: [String]?

    var categoryLabel: String { AircraftCategory.label(for: category) }
}

struct Quote: Codable, Hashable, Identifiable {
    let id: String
    let status: String
    let operatorInfo: QuoteOperator
    let aircraft: QuoteAircraft
    let priceCents: Int
    let currency: String
    let departsAt: Date
    let durationMin: Int
    let message: String?
    let expiresAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status, aircraft, priceCents, currency, departsAt, durationMin, message, expiresAt, createdAt
        case operatorInfo = "operator"
    }

    var quoteStatus: QuoteStatus? { QuoteStatus(rawValue: status) }
    var isPending: Bool { status == QuoteStatus.pending.rawValue }
    func isLive(at now: Date = Date()) -> Bool { isPending && expiresAt > now }
    var priceText: String { Money.format(cents: priceCents, currency: currency) }
    var durationText: String { DurationText.text(minutes: durationMin) }

    func with(status newStatus: QuoteStatus) -> Quote {
        Quote(id: id, status: newStatus.rawValue, operatorInfo: operatorInfo, aircraft: aircraft,
              priceCents: priceCents, currency: currency, departsAt: departsAt, durationMin: durationMin,
              message: message, expiresAt: expiresAt, createdAt: createdAt)
    }
}

/// `TripRequest` as the customer sees it. The operator inbox returns the same object with
/// `myQuote` + `quoteCount` and without other operators' `quotes`, so those three are optional.
struct TripRequest: Codable, Hashable, Identifiable {
    let id: String
    let status: String
    let origin: Airport
    let destination: Airport
    let departAfter: Date
    let departBefore: Date
    let passengers: Int
    let category: String?
    let maxPriceCents: Int?
    let currency: String
    let notes: String?
    let createdAt: Date
    let expiresAt: Date
    let quotes: [Quote]?
    let bookingId: String?
    let myQuote: Quote?
    let quoteCount: Int?

    var requestStatus: TripRequestStatus? { TripRequestStatus(rawValue: status) }
    var statusLabel: String { requestStatus?.label ?? status.capitalized }
    var allQuotes: [Quote] { quotes ?? [] }
    var isActive: Bool { (status == "OPEN" || status == "QUOTED") && expiresAt > Date() }
    var routeCode: String { "\(origin.iata) → \(destination.iata)" }
    var cityPair: String { "\(origin.city) → \(destination.city)" }
    var categoryLabel: String { category.map { AircraftCategory.label(for: $0) } ?? "Any aircraft" }
    var maxPriceText: String? { maxPriceCents.map { Money.format(cents: $0, currency: currency) } }
    var windowText: String {
        "\(DateText.departure(departAfter, timezone: origin.timezone)) – \(DateText.departure(departBefore, timezone: origin.timezone))"
    }

    /// Pending, unexpired quotes, cheapest first.
    func liveQuotes(at now: Date = Date()) -> [Quote] {
        allQuotes.filter { $0.isLive(at: now) }.sorted { $0.priceCents < $1.priceCents }
    }

    var effectiveQuoteCount: Int { quoteCount ?? allQuotes.count }

    func with(status: TripRequestStatus? = nil, quotes newQuotes: [Quote]? = nil, bookingId newBookingId: String? = nil,
              myQuote newMyQuote: Quote?? = nil, quoteCount newCount: Int? = nil) -> TripRequest {
        TripRequest(id: id, status: status?.rawValue ?? self.status, origin: origin, destination: destination,
                    departAfter: departAfter, departBefore: departBefore, passengers: passengers,
                    category: category, maxPriceCents: maxPriceCents, currency: currency, notes: notes,
                    createdAt: createdAt, expiresAt: expiresAt, quotes: newQuotes ?? quotes,
                    bookingId: newBookingId ?? bookingId,
                    myQuote: newMyQuote ?? myQuote, quoteCount: newCount ?? quoteCount)
    }
}

/// `{ items: [...] }` list envelope used by the Uber-mode list endpoints.
struct ItemsEnvelope<T: Codable>: Codable {
    let items: [T]
}

/// `POST /v1/trip-requests` body.
struct CreateTripRequestBody: Encodable {
    let originIata: String
    let destinationIata: String
    let departAfter: Date
    let departBefore: Date
    let passengers: Int
    let category: String?
    let maxPriceCents: Int?
    let notes: String?
}

/// `POST /v1/trip-requests/:id/quotes/:quoteId/accept` → `{ tripRequest, booking }`.
struct AcceptQuoteResponse: Decodable {
    let tripRequest: TripRequest
    let booking: Booking
}

// MARK: Operator side

/// `POST /v1/operator/requests/:id/quotes` body.
struct CreateQuoteBody: Encodable {
    let aircraftId: String
    let priceCents: Int
    let departsAt: Date
    let durationMin: Int
    let message: String?
    let expiresInMinutes: Int?
}

/// `GET /v1/operator/quotes` item: a Quote with its `tripRequest` embedded.
struct OperatorQuote: Codable, Hashable, Identifiable {
    let quote: Quote
    let tripRequest: TripRequest?

    var id: String { quote.id }

    private enum CodingKeys: String, CodingKey { case tripRequest }

    init(quote: Quote, tripRequest: TripRequest?) {
        self.quote = quote
        self.tripRequest = tripRequest
    }

    init(from decoder: Decoder) throws {
        quote = try Quote(from: decoder)
        tripRequest = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(TripRequest.self, forKey: .tripRequest)
    }

    func encode(to encoder: Encoder) throws {
        try quote.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(tripRequest, forKey: .tripRequest)
    }
}

// MARK: Live trip status

enum TripStatus: String, Codable, CaseIterable, Identifiable {
    case confirmed = "CONFIRMED"
    case crewAssigned = "CREW_ASSIGNED"
    case boarding = "BOARDING"
    case departed = "DEPARTED"
    case arrived = "ARRIVED"
    case cancelled = "CANCELLED"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .confirmed: return "Confirmed"
        case .crewAssigned: return "Crew assigned"
        case .boarding: return "Boarding"
        case .departed: return "Departed"
        case .arrived: return "Arrived"
        case .cancelled: return "Cancelled"
        }
    }

    var systemImage: String {
        switch self {
        case .confirmed: return "checkmark.seal"
        case .crewAssigned: return "person.2.badge.gearshape"
        case .boarding: return "figure.walk.arrival"
        case .departed: return "airplane.departure"
        case .arrived: return "airplane.arrival"
        case .cancelled: return "xmark.octagon"
        }
    }

    /// The happy path, in order (cancelled is off-path).
    static let progression: [TripStatus] = [.confirmed, .crewAssigned, .boarding, .departed, .arrived]

    var next: TripStatus? {
        guard let i = Self.progression.firstIndex(of: self), i + 1 < Self.progression.count else { return nil }
        return Self.progression[i + 1]
    }
}

struct TrackingEvent: Codable, Hashable {
    let status: String
    let at: Date
    let note: String?

    var tripStatus: TripStatus? { TripStatus(rawValue: status) }
}

struct TrackingPosition: Codable, Hashable {
    let lat: Double
    let lng: Double
    let updatedAt: Date
}

struct TrackingOperator: Codable, Hashable {
    let id: String
    let displayName: String
}

struct TrackingAircraft: Codable, Hashable {
    let model: String
    let registration: String?
    let category: String
}

/// `GET /v1/bookings/:id/track` and `PATCH /v1/operator/bookings/:id/status` response.
struct Tracking: Codable, Hashable {
    let bookingId: String
    let reference: String
    let tripStatus: String?
    let events: [TrackingEvent]
    let position: TrackingPosition?
    let etaMinutes: Int?
    let origin: Airport
    let destination: Airport
    let departsAt: Date
    let durationMin: Int
    let operatorInfo: TrackingOperator
    let aircraft: TrackingAircraft

    enum CodingKeys: String, CodingKey {
        case bookingId, reference, tripStatus, events, position, etaMinutes, origin, destination
        case departsAt, durationMin, aircraft
        case operatorInfo = "operator"
    }

    var status: TripStatus? { tripStatus.flatMap(TripStatus.init(rawValue:)) }
    /// "Scheduled" until the operator posts the first update.
    var statusLabel: String { status?.label ?? "Scheduled" }

    func event(for status: TripStatus) -> TrackingEvent? {
        events.last { $0.status == status.rawValue }
    }
}

/// `PATCH /v1/operator/bookings/:id/status` body.
struct StatusUpdateBody: Encodable {
    let status: TripStatus
    let lat: Double?
    let lng: Double?
    let etaMinutes: Int?
    let note: String?
}

/// `POST /v1/devices` body.
struct DeviceRegistrationBody: Encodable {
    let platform: String
    let token: String
}

struct OkResponse: Decodable {
    let ok: Bool
}

enum DurationText {
    static func text(minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }
}
