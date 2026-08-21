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

    /// Mock payment: `POST /pay` then `POST /confirm-mock`. Locally this just flips the status.
    func payAndConfirm(_ booking: Booking) async throws -> Booking {
        if mode.isSample || booking.id.hasPrefix("local_") {
            let payment = Payment(id: "local_pay_\(booking.id)", provider: "MOCK", status: "SUCCEEDED",
                                  amountCents: booking.totalCents, currency: booking.currency)
            let confirmed = booking.withStatus(.confirmed, payment: payment)
            upsertLocal(confirmed)
            return confirmed
        }
        let pay: PayResponse = try await api.post("/bookings/\(booking.id)/pay", auth: true)
        guard pay.isMock else {
            throw APIError.server(statusCode: 501, message: "Live card payments aren't available in this build yet.")
        }
        let confirmed: Booking = try await api.post("/bookings/\(booking.id)/confirm-mock", auth: true)
        upsert(confirmed)
        return confirmed
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
