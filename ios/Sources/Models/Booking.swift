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

/// Payment rails exposed by `GET /v1/payments/methods`.
enum PaymentRail: String, Codable, CaseIterable, Identifiable {
    case card = "CARD"
    case paypal = "PAYPAL"
    case klarna = "KLARNA"
    case crypto = "CRYPTO"

    var id: String { rawValue }

    /// Fallback label when the server does not send one.
    var defaultLabel: String {
        switch self {
        case .card: return "Card"
        case .paypal: return "PayPal"
        case .klarna: return "Klarna"
        case .crypto: return "Crypto"
        }
    }

    var systemImage: String {
        switch self {
        case .card: return "creditcard"
        case .paypal: return "p.circle"
        case .klarna: return "k.square"
        case .crypto: return "bitcoinsign.circle"
        }
    }

    /// Stable tab order regardless of how the API lists the methods.
    static let displayOrder: [PaymentRail] = [.card, .paypal, .klarna, .crypto]
}

/// One entry of `GET /v1/payments/methods?currency=USD`.
struct PaymentMethodInfo: Decodable, Hashable, Identifiable {
    let method: PaymentRail
    let enabled: Bool
    let mode: String
    let label: String?
    let note: String?

    var id: PaymentRail { method }
    var title: String { label ?? method.defaultLabel }
    var isMock: Bool { mode == "mock" }

    static func mock(_ rail: PaymentRail, note: String) -> PaymentMethodInfo {
        PaymentMethodInfo(method: rail, enabled: true, mode: "mock", label: rail.defaultLabel, note: note)
    }

    /// Fallback when the methods endpoint fails: card only, in whatever mode `/meta` reported.
    static func cardOnly(mode: String) -> [PaymentMethodInfo] {
        [PaymentMethodInfo(method: .card, enabled: true, mode: mode, label: "Card", note: nil)]
    }

    static func sorted(_ methods: [PaymentMethodInfo]) -> [PaymentMethodInfo] {
        methods.sorted {
            (PaymentRail.displayOrder.firstIndex(of: $0.method) ?? 99)
                < (PaymentRail.displayOrder.firstIndex(of: $1.method) ?? 99)
        }
    }
}

enum CryptoAsset: String, Codable, CaseIterable, Identifiable {
    case btc = "BTC"
    case eth = "ETH"
    case usdc = "USDC"
    case usdt = "USDT"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .btc: return "Bitcoin"
        case .eth: return "Ethereum"
        case .usdc: return "USD Coin"
        case .usdt: return "Tether"
        }
    }

    var network: String {
        switch self {
        case .btc: return "Bitcoin"
        case .eth: return "Ethereum"
        case .usdc, .usdt: return "Ethereum (ERC-20)"
        }
    }
}

/// `POST /v1/bookings/:id/pay` body.
struct PayRequest: Encodable {
    let method: PaymentRail
    let crypto: CryptoAsset?
}

/// Rate-locked crypto charge returned inside `PayResponse.crypto`.
struct CryptoCharge: Decodable, Hashable {
    let asset: CryptoAsset
    let amount: String
    let address: String
    let expiresAt: Date
    let rateLocked: String
    let hostedUrl: String?

    /// "2.38486333" → "2.38486333", "0.01230000" → "0.0123".
    var amountText: String {
        guard amount.contains(".") else { return amount }
        var trimmed = amount
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed
    }
}

/// `POST /v1/bookings/:id/pay` → `{ method, mode, paymentId, amountCents, currency, clientSecret?, redirectUrl?, crypto? }`.
struct PayResponse: Decodable {
    let method: PaymentRail?
    let mode: String
    let paymentId: String?
    let amountCents: Int?
    let currency: String?
    let clientSecret: String?
    let redirectUrl: String?
    let crypto: CryptoCharge?

    var isMock: Bool { mode == "mock" }

    /// Approval page to open in Safari for a live PayPal order.
    var approvalURL: URL? {
        guard let redirectUrl = redirectUrl, let url = URL(string: redirectUrl),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        return url
    }
}
