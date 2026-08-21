import Foundation

enum AircraftCategory: String, CaseIterable, Identifiable {
    case lightJet = "LIGHT_JET"
    case midsize = "MIDSIZE"
    case superMidsize = "SUPER_MIDSIZE"
    case heavyJet = "HEAVY_JET"
    case turboprop = "TURBOPROP"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lightJet: return "Light Jet"
        case .midsize: return "Midsize"
        case .superMidsize: return "Super Midsize"
        case .heavyJet: return "Heavy Jet"
        case .turboprop: return "Turboprop"
        }
    }

    static func label(for raw: String) -> String {
        AircraftCategory(rawValue: raw)?.label
            ?? raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct AircraftSummary: Codable, Hashable {
    let id: String
    let model: String
    let category: String
    let seats: Int
    let images: [String]
    let amenities: [String]
    let registration: String?

    var categoryLabel: String { AircraftCategory.label(for: category) }
}

struct OperatorSummary: Codable, Hashable {
    let id: String
    let displayName: String
    let slug: String
    let verificationStatus: String
    let yearsOperating: Int?
    let flightsCompleted: Int?
    let description: String?
    let regulator: String?

    var isVerified: Bool { verificationStatus == "VERIFIED" }
}

struct Flight: Codable, Hashable, Identifiable {
    let id: String
    let operatorId: String
    let aircraftId: String
    let originId: String
    let destinationId: String
    let departsAt: Date
    let durationMin: Int
    let seatsTotal: Int
    let seatsAvailable: Int
    let basePriceCents: Int
    let currency: String
    let description: String?
    let status: String
    let origin: Airport
    let destination: Airport
    let aircraft: AircraftSummary
    let operatorInfo: OperatorSummary

    enum CodingKeys: String, CodingKey {
        case id, operatorId, aircraftId, originId, destinationId, departsAt, durationMin
        case seatsTotal, seatsAvailable, basePriceCents, currency, description, status
        case origin, destination, aircraft
        case operatorInfo = "operator"
    }

    var routeCode: String { "\(origin.iata) → \(destination.iata)" }
    var routeTitle: String { "\(origin.label) → \(destination.label)" }
    var cityPair: String { "\(origin.city) → \(destination.city)" }
    var priceText: String { Money.format(cents: basePriceCents, currency: currency) }

    var durationText: String {
        let h = durationMin / 60
        let m = durationMin % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    var departsText: String {
        DateText.departure(departsAt, timezone: origin.timezone)
    }

    var departsDayText: String {
        DateText.day(departsAt, timezone: origin.timezone)
    }

    var departsTimeText: String {
        DateText.time(departsAt, timezone: origin.timezone)
    }

    /// Returns a copy with a different availability (used by local sample bookings).
    func withSeatsAvailable(_ seats: Int) -> Flight {
        Flight(id: id, operatorId: operatorId, aircraftId: aircraftId, originId: originId,
               destinationId: destinationId, departsAt: departsAt, durationMin: durationMin,
               seatsTotal: seatsTotal, seatsAvailable: seats, basePriceCents: basePriceCents,
               currency: currency, description: description, status: status, origin: origin,
               destination: destination, aircraft: aircraft, operatorInfo: operatorInfo)
    }
}

/// `GET /v1/flights` response: `{ items, total, page, pageSize }`.
struct FlightPage: Codable {
    let items: [Flight]
    let total: Int
    let page: Int
    let pageSize: Int
}

/// `GET /v1/flights/:id`: the flight itself plus `similar[]`.
struct FlightDetail: Decodable {
    let flight: Flight
    let similar: [Flight]

    private enum CodingKeys: String, CodingKey {
        case similar
    }

    init(flight: Flight, similar: [Flight]) {
        self.flight = flight
        self.similar = similar
    }

    init(from decoder: Decoder) throws {
        flight = try Flight(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        similar = try container.decodeIfPresent([Flight].self, forKey: .similar) ?? []
    }
}

struct FlightQuery: Equatable {
    var from: String = ""
    var to: String = ""
    var categories: Set<String> = []
    var minSeats: Int = 1

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        let f = from.trimmingCharacters(in: .whitespaces).uppercased()
        let t = to.trimmingCharacters(in: .whitespaces).uppercased()
        if !f.isEmpty { items.append(URLQueryItem(name: "from", value: f)) }
        if !t.isEmpty { items.append(URLQueryItem(name: "to", value: t)) }
        if !categories.isEmpty {
            items.append(URLQueryItem(name: "category", value: categories.sorted().joined(separator: ",")))
        }
        if minSeats > 1 { items.append(URLQueryItem(name: "minSeats", value: String(minSeats))) }
        items.append(URLQueryItem(name: "pageSize", value: "50"))
        return items
    }

    /// Local filter used in sample mode.
    func matches(_ flight: Flight) -> Bool {
        let f = from.trimmingCharacters(in: .whitespaces).uppercased()
        let t = to.trimmingCharacters(in: .whitespaces).uppercased()
        if !f.isEmpty && flight.origin.iata != f { return false }
        if !t.isEmpty && flight.destination.iata != t { return false }
        if !categories.isEmpty && !categories.contains(flight.aircraft.category) { return false }
        if flight.seatsAvailable < minSeats { return false }
        return true
    }
}
