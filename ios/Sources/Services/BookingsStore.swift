import Foundation
import Combine

@MainActor
final class BookingsStore: ObservableObject {
    @Published private(set) var bookings: [Booking] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var usingSampleData = false

    private static let localKey = "sampleBookings.v1"
    private static let holdMinutes: TimeInterval = 15
    private static let serviceFeeBps = 300
    private static let taxBps = 215

    private let api = APIClient.shared
    private let mode = AppMode.shared

    init() {
        loadLocal()
    }

    // MARK: Loading

    func load(signedIn: Bool) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if mode.forced || !signedIn {
            loadLocal()
            usingSampleData = true
            return
        }
        do {
            let remote: [Booking] = try await api.get("/bookings", auth: true)
            bookings = remote.sorted { $0.createdAt > $1.createdAt }
            usingSampleData = false
            mode.offline = false
        } catch let error as APIError where error.isUnreachable {
            mode.offline = true
            loadLocal()
            usingSampleData = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Booking flow

    /// Creates a HELD booking — on the server, or locally in sample mode.
    func createBooking(flight: Flight, passengers: Int) async throws -> Booking {
        if mode.isSample {
            let booking = makeLocalHold(flight: flight, passengers: passengers)
            upsertLocal(booking)
            return booking
        }
        let request = CreateBookingRequest(flightId: flight.id, passengers: passengers)
        let booking: Booking = try await api.post("/bookings", body: request, auth: true)
        upsert(booking)
        return booking
    }

    // MARK: Payment rails

    /// Rails for the checkout tabs. Sample mode uses the bundled capture (all four, mock);
    /// a failed request falls back to card only so checkout never dead-ends.
    func paymentMethods(currency: String) async -> [PaymentMethodInfo] {
        if mode.isSample {
            return PaymentMethodInfo.sorted(SampleData.paymentMethods())
        }
        do {
            let methods: [PaymentMethodInfo] = try await api.get(
                "/payments/methods", query: [URLQueryItem(name: "currency", value: currency)], auth: true)
            return PaymentMethodInfo.sorted(methods)
        } catch let error as APIError where error.isUnreachable {
            mode.offline = true
            return PaymentMethodInfo.sorted(SampleData.paymentMethods())
        } catch {
            return PaymentMethodInfo.cardOnly(mode: mode.serverMeta?.paymentMode ?? "mock")
        }
    }

    /// `POST /pay` for the chosen rail. Local bookings get a generated mock response.
    func startPayment(_ booking: Booking, rail: PaymentRail, crypto: CryptoAsset? = nil) async throws -> PayResponse {
        if isLocal(booking) {
            return Self.localPayResponse(for: booking, rail: rail, crypto: crypto)
        }
        return try await api.post("/bookings/\(booking.id)/pay", body: PayRequest(method: rail, crypto: crypto), auth: true)
    }

    /// Card / Klarna checkout: `/pay` then `/confirm-mock` when the rail is in mock mode.
    func payAndConfirm(_ booking: Booking, rail: PaymentRail) async throws -> Booking {
        let pay = try await startPayment(booking, rail: rail)
        guard pay.isMock else {
            throw APIError.server(statusCode: 501, message: "Live \(rail.defaultLabel) payments aren't available in this build yet.")
        }
        return try await confirmMock(booking)
    }

    /// Completes a mock CARD / KLARNA / CRYPTO payment (`POST /confirm-mock`).
    func confirmMock(_ booking: Booking) async throws -> Booking {
        if isLocal(booking) {
            return confirmLocally(booking, provider: "MOCK")
        }
        let confirmed: Booking = try await api.post("/bookings/\(booking.id)/confirm-mock", auth: true)
        upsert(confirmed)
        return confirmed
    }

    /// Captures an approved PayPal order (`POST /paypal/capture`).
    func capturePayPal(_ booking: Booking) async throws -> Booking {
        if isLocal(booking) {
            return confirmLocally(booking, provider: "PAYPAL")
        }
        let confirmed: Booking = try await api.post("/bookings/\(booking.id)/paypal/capture", auth: true)
        upsert(confirmed)
        return confirmed
    }

    /// Latest server state for one booking (used while waiting on a live crypto payment).
    func refresh(_ booking: Booking) async throws -> Booking {
        if isLocal(booking) { return bookings.first { $0.id == booking.id } ?? booking }
        let latest: Booking = try await api.get("/bookings/\(booking.id)", auth: true)
        upsert(latest)
        return latest
    }

    private func isLocal(_ booking: Booking) -> Bool {
        mode.isSample || booking.id.hasPrefix("local_")
    }

    private func confirmLocally(_ booking: Booking, provider: String) -> Booking {
        let payment = Payment(id: "local_pay_\(booking.id)", provider: provider, status: "SUCCEEDED",
                              amountCents: booking.totalCents, currency: booking.currency)
        let confirmed = booking.withStatus(.confirmed, payment: payment)
        upsertLocal(confirmed)
        return confirmed
    }

    /// Mirrors the API's mock responses: PayPal gets a placeholder approval URL, crypto a simulated
    /// rate-locked charge with a 15-minute expiry, card/Klarna a mock client secret.
    private static func localPayResponse(for booking: Booking, rail: PaymentRail, crypto: CryptoAsset?) -> PayResponse {
        let paymentId = "local_pay_\(booking.id)"
        switch rail {
        case .paypal:
            return PayResponse(method: rail, mode: "mock", paymentId: paymentId, amountCents: booking.totalCents,
                               currency: booking.currency, clientSecret: nil,
                               redirectUrl: "lastleg://book/\(booking.id)/paypal-mock", crypto: nil)
        case .crypto:
            let asset = crypto ?? .btc
            let rate = localRate(for: asset)
            let amount = Double(booking.totalCents) / 100.0 / rate
            let charge = CryptoCharge(asset: asset,
                                      amount: String(format: "%.8f", amount),
                                      address: localAddress(for: asset, seed: booking.id),
                                      expiresAt: Date().addingTimeInterval(holdMinutes * 60),
                                      rateLocked: "1 \(asset.rawValue) = \(String(format: "%.2f", rate)) \(booking.currency)",
                                      hostedUrl: nil)
            return PayResponse(method: rail, mode: "mock", paymentId: paymentId, amountCents: booking.totalCents,
                               currency: booking.currency, clientSecret: nil, redirectUrl: nil, crypto: charge)
        case .card, .klarna:
            return PayResponse(method: rail, mode: "mock", paymentId: paymentId, amountCents: booking.totalCents,
                               currency: booking.currency, clientSecret: "mock_secret_\(booking.id)",
                               redirectUrl: nil, crypto: nil)
        }
    }

    /// Same fixed quotes the API uses in mock mode (per unit, in the booking currency).
    private static func localRate(for asset: CryptoAsset) -> Double {
        switch asset {
        case .btc: return 60_000
        case .eth: return 3_000
        case .usdc, .usdt: return 1
        }
    }

    /// Deterministic fake wallet address per asset so the demo looks stable across re-renders.
    private static func localAddress(for asset: CryptoAsset, seed: String) -> String {
        let hexAlphabet = Array("0123456789abcdef")
        let bech32Alphabet = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
        var state = UInt64(truncatingIfNeeded: seed.utf8.reduce(5381) { ($0 &* 33) &+ UInt64($1) })
        func next() -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int(state >> 33)
        }
        switch asset {
        case .btc:
            return "bc1q" + (0..<38).map { _ in String(bech32Alphabet[next() % bech32Alphabet.count]) }.joined()
        case .eth, .usdc, .usdt:
            return "0x" + (0..<40).map { _ in String(hexAlphabet[next() % hexAlphabet.count]) }.joined()
        }
    }

    // MARK: Local (sample) bookings

    private func makeLocalHold(flight: Flight, passengers: Int) -> Booking {
        let base = flight.basePriceCents
        let fee = Int((Double(base) * Double(Self.serviceFeeBps) / 10_000).rounded())
        let tax = Int((Double(base + fee) * Double(Self.taxBps) / 10_000).rounded())
        let now = Date()
        return Booking(
            id: "local_\(UUID().uuidString.lowercased())",
            reference: Self.makeReference(),
            flightId: flight.id,
            customerId: SampleData.guestUser.id,
            passengers: passengers,
            status: BookingStatus.held.rawValue,
            holdExpiresAt: now.addingTimeInterval(Self.holdMinutes * 60),
            baseFareCents: base,
            serviceFeeCents: fee,
            taxCents: tax,
            totalCents: base + fee + tax,
            currency: flight.currency,
            createdAt: now,
            flight: flight.withSeatsAvailable(max(0, flight.seatsAvailable - passengers)),
            payment: nil
        )
    }

    /// `LLJ-` plus 6 unambiguous uppercase characters, matching the server format.
    static func makeReference() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let suffix = (0..<6).map { _ in String(alphabet[Int.random(in: 0..<alphabet.count)]) }.joined()
        return "LLJ-\(suffix)"
    }

    private func upsert(_ booking: Booking) {
        if let index = bookings.firstIndex(where: { $0.id == booking.id }) {
            bookings[index] = booking
        } else {
            bookings.insert(booking, at: 0)
        }
    }

    private func upsertLocal(_ booking: Booking) {
        upsert(booking)
        saveLocal()
    }

    private func loadLocal() {
        guard let data = UserDefaults.standard.data(forKey: Self.localKey),
              let saved = try? APIClient.decoder.decode([Booking].self, from: data) else {
            bookings = []
            return
        }
        let now = Date()
        bookings = saved.map { booking in
            booking.isHeld && booking.holdExpiresAt < now ? booking.withStatus(.expired) : booking
        }
    }

    private func saveLocal() {
        let local = bookings.filter { $0.id.hasPrefix("local_") }
        if let data = try? APIClient.encoder.encode(local) {
            UserDefaults.standard.set(data, forKey: Self.localKey)
        }
    }
}
