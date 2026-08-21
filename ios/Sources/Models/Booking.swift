import Foundation

enum BookingStatus: String {
    case held = "HELD"
    case confirmed = "CONFIRMED"
    case expired = "EXPIRED"
    case cancelled = "CANCELLED"
    case refunded = "REFUNDED"

    var label: String {
        switch self {
        case .held: return "Held"
        case .confirmed: return "Confirmed"
        case .expired: return "Expired"
        case .cancelled: return "Cancelled"
        case .refunded: return "Refunded"
        }
    }
}

struct Payment: Codable, Hashable {
    let id: String
    let provider: String
    let status: String
    let amountCents: Int
    let currency: String
}

struct Booking: Codable, Hashable, Identifiable {
    let id: String
    let reference: String
    let flightId: String
    let customerId: String
    let passengers: Int
    let status: String
    let holdExpiresAt: Date
    let baseFareCents: Int
    let serviceFeeCents: Int
    let taxCents: Int
    let totalCents: Int
    let currency: String
    let createdAt: Date
    let flight: Flight?
    let payment: Payment?

    var bookingStatus: BookingStatus? { BookingStatus(rawValue: status) }
    var statusLabel: String { bookingStatus?.label ?? status.capitalized }
    var isHeld: Bool { status == BookingStatus.held.rawValue }
    var isConfirmed: Bool { status == BookingStatus.confirmed.rawValue }

    var baseFareText: String { Money.format(cents: baseFareCents, currency: currency) }
    var serviceFeeText: String { Money.format(cents: serviceFeeCents, currency: currency) }
    var taxText: String { Money.format(cents: taxCents, currency: currency) }
    var totalText: String { Money.format(cents: totalCents, currency: currency) }

    func withStatus(_ newStatus: BookingStatus, payment newPayment: Payment? = nil) -> Booking {
        Booking(id: id, reference: reference, flightId: flightId, customerId: customerId,
                passengers: passengers, status: newStatus.rawValue, holdExpiresAt: holdExpiresAt,
                baseFareCents: baseFareCents, serviceFeeCents: serviceFeeCents, taxCents: taxCents,
                totalCents: totalCents, currency: currency, createdAt: createdAt, flight: flight,
                payment: newPayment ?? payment)
    }
}

struct CreateBookingRequest: Encodable {
    let flightId: String
    let passengers: Int
}

/// `POST /v1/bookings/:id/pay` → `{ mode: "stripe"|"mock", clientSecret, ... }`.
struct PayResponse: Decodable {
    let mode: String
    let clientSecret: String?
    let paymentId: String?
    let amountCents: Int?
    let currency: String?

    var isMock: Bool { mode == "mock" }
}

enum PaymentMethod: String, CaseIterable, Identifiable {
    case card = "Card"
    case paypal = "PayPal"
    case klarna = "Klarna"
    case crypto = "Crypto"

    var id: String { rawValue }
    var isAvailable: Bool { self == .card }
}
