import Foundation

/// `GET /v1/operator/me`.
struct OperatorProfile: Codable, Hashable {
    let id: String
    let displayName: String
    let slug: String?
    let description: String?
    let regulator: String?
    let aocNumber: String?
    let yearsOperating: Int?
    let flightsCompleted: Int?
    let verificationStatus: String
    let payoutsEnabled: Bool?

    var isVerified: Bool { verificationStatus == "VERIFIED" }
}

/// `GET /v1/operator/aircraft` item.
struct Aircraft: Codable, Hashable, Identifiable {
    let id: String
    let registration: String?
    let model: String
    let category: String
    let seats: Int
    let images: [String]?
    let amenities: [String]?

    var categoryLabel: String { AircraftCategory.label(for: category) }
    var title: String { registration.map { "\(model) · \($0)" } ?? model }
}

/// `POST /v1/operator/aircraft` body.
struct CreateAircraftBody: Encodable {
    let model: String
    let category: String
    let seats: Int
    let registration: String?
    let amenities: [String]?
}

/// `POST /v1/operator/flights` body (IATA variant of the existing DTO).
struct CreateFlightBody: Encodable {
    let aircraftId: String
    let originIata: String
    let destinationIata: String
    let departsAt: Date
    let durationMin: Int
    let basePriceCents: Int
    let currency: String
    let seatsTotal: Int?
    let description: String?
}

struct PayoutRecord: Codable, Hashable, Identifiable {
    let id: String
    let amountCents: Int
    let currency: String
    let status: String
    let providerRef: String?
    let createdAt: Date
    let paidAt: Date?

    var amountText: String { Money.format(cents: amountCents, currency: currency) }
}

/// `GET /v1/operator/payouts`.
struct PayoutSummary: Codable, Hashable {
    let mode: String
    let accountId: String?
    let payoutsEnabled: Bool
    let pendingBookings: Int
    let pendingNetByCurrency: [String: Int]
    let payouts: [PayoutRecord]

    /// Paid payouts per currency.
    var paidByCurrency: [String: Int] {
        payouts.filter { $0.status == "PAID" }.reduce(into: [:]) { $0[$1.currency, default: 0] += $1.amountCents }
    }

    var pendingText: String { Self.text(pendingNetByCurrency) }
    var paidText: String { Self.text(paidByCurrency) }

    static func text(_ byCurrency: [String: Int]) -> String {
        guard !byCurrency.isEmpty else { return Money.format(cents: 0, currency: "USD") }
        return byCurrency.keys.sorted().map { Money.format(cents: byCurrency[$0] ?? 0, currency: $0) }.joined(separator: " + ")
    }
}

/// Customer block that `/operator/bookings` embeds in each booking.
struct BookingCustomer: Codable, Hashable {
    let id: String
    let email: String
    let firstName: String
    let lastName: String

    var fullName: String {
        let name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? email : name
    }
}

enum Geo {
    /// Great-circle distance in kilometres.
    static func distanceKm(lat1: Double, lng1: Double, lat2: Double, lng2: Double) -> Double {
        let r = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }

    static func distanceKm(_ a: Airport, _ b: Airport) -> Double {
        distanceKm(lat1: a.lat, lng1: a.lng, lat2: b.lat, lng2: b.lng)
    }

    /// Initial bearing in degrees (0 = north, clockwise).
    static func bearing(lat1: Double, lng1: Double, lat2: Double, lng2: Double) -> Double {
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dl = (lng2 - lng1) * .pi / 180
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Point a fraction `t` (0...1) along the great circle from a to b.
    static func interpolate(lat1: Double, lng1: Double, lat2: Double, lng2: Double, t: Double) -> (lat: Double, lng: Double) {
        let p1 = lat1 * .pi / 180, l1 = lng1 * .pi / 180
        let p2 = lat2 * .pi / 180, l2 = lng2 * .pi / 180
        let d = distanceKm(lat1: lat1, lng1: lng1, lat2: lat2, lng2: lng2) / 6371.0
        guard d > 1e-9 else { return (lat1, lng1) }
        let a = sin((1 - t) * d) / sin(d)
        let b = sin(t * d) / sin(d)
        let x = a * cos(p1) * cos(l1) + b * cos(p2) * cos(l2)
        let y = a * cos(p1) * sin(l1) + b * cos(p2) * sin(l2)
        let z = a * sin(p1) + b * sin(p2)
        return (atan2(z, sqrt(x * x + y * y)) * 180 / .pi, atan2(y, x) * 180 / .pi)
    }

    /// Rough block time for a charter at ~780 km/h plus 20 minutes taxi/climb.
    static func estimatedMinutes(_ a: Airport, _ b: Airport) -> Int {
        let minutes = distanceKm(a, b) / 780.0 * 60.0 + 20
        return max(30, Int((minutes / 5).rounded()) * 5)
    }
}
