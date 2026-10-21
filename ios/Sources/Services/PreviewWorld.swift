import Foundation

/// On-device stand-in for the Uber-mode API, used in sample mode, when the server is unreachable,
/// or when the server doesn't have the new routes yet (Nest "Cannot GET" 404).
///
/// Customer and operator share one world, so on a single phone you can request a trip as the
/// traveller, quote it from the Operator tab, accept the quote, and advance the trip status.
/// Requests created here (ids `local_…`) also collect simulated quotes from other operators.
@MainActor
final class PreviewWorld {
    static let shared = PreviewWorld()

    struct State: Codable {
        var version: Int
        /// Customer-side requests (seeded + created on this device), newest first.
        var requests: [TripRequest]
        /// Operator inbox requests from other customers (seeded).
        var inbox: [TripRequest]
        /// Quotes "my" operator has sent.
        var myQuotes: [OperatorQuote]
        var flights: [Flight]
        var aircraft: [Aircraft]
        /// Charter bookings visible to both sides.
        var bookings: [Booking]
        /// Operator status updates by booking id.
        var tracking: [String: Tracking]
        var payouts: PayoutSummary?
        var profile: OperatorProfile?
    }

    private static let storageKey = "previewWorld.v1"
    private static let stateVersion = 1
    /// Simulated operators that answer requests created on this device (seconds after creation).
    private static let botSchedule: [TimeInterval] = [5, 12, 21]

    private(set) var state: State

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? APIClient.decoder.decode(State.self, from: data),
           saved.version == Self.stateVersion {
            state = saved
        } else {
            state = Self.seed()
        }
    }

    static func seed() -> State {
        State(version: stateVersion,
              requests: SampleData.tripRequests(),
              inbox: SampleData.operatorRequests().filter { r in
                  !SampleData.tripRequests().contains { $0.id == r.id }
              },
              myQuotes: SampleData.operatorQuotes(),
              flights: SampleData.operatorFlights(),
              aircraft: SampleData.operatorAircraft(),
              bookings: SampleData.tripBookings(),
              tracking: [:],
              payouts: SampleData.operatorPayouts(),
              profile: SampleData.operatorProfile())
    }

    /// Back to the bundled scenario (Account → "Reset preview data").
    func reset() {
        state = Self.seed()
        save()
    }

    private func save() {
        if let data = try? APIClient.encoder.encode(state) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    // MARK: Customer

    func customerRequests(now: Date = Date()) -> [TripRequest] {
        simulate(now: now)
        return state.requests.map { expireIfNeeded($0, now: now) }
    }

    func request(id: String, now: Date = Date()) -> TripRequest? {
        customerRequests(now: now).first { $0.id == id }
    }

    func createRequest(_ body: CreateTripRequestBody, now: Date = Date()) throws -> TripRequest {
        guard let origin = airport(body.originIata), let destination = airport(body.destinationIata) else {
            throw APIError.server(statusCode: 400, message: "Pick airports from the list.")
        }
        guard origin.iata != destination.iata else {
            throw APIError.server(statusCode: 400, message: "Origin and destination must differ.")
        }
        let expires = min(body.departBefore, now.addingTimeInterval(24 * 3600))
        let request = TripRequest(id: "local_req_\(UUID().uuidString.prefix(8).lowercased())", status: TripRequestStatus.open.rawValue,
                                  origin: origin, destination: destination,
                                  departAfter: body.departAfter, departBefore: body.departBefore,
                                  passengers: body.passengers, category: body.category,
                                  maxPriceCents: body.maxPriceCents, currency: "USD", notes: body.notes,
                                  createdAt: now, expiresAt: expires, quotes: [], bookingId: nil,
                                  myQuote: nil, quoteCount: nil)
        state.requests.insert(request, at: 0)
        save()
        return request
    }

    func cancelRequest(id: String) -> TripRequest? {
        guard let i = state.requests.firstIndex(where: { $0.id == id }) else { return nil }
        let quotes = state.requests[i].allQuotes.map { $0.isPending ? $0.with(status: .declined) : $0 }
        state.requests[i] = state.requests[i].with(status: .cancelled, quotes: quotes)
        save()
        return state.requests[i]
    }

    /// Accepting builds the charter Flight the API would create, then returns it with the updated
    /// request; the caller turns the flight into a HELD booking through `BookingsStore`.
    func flightForAccepting(requestId: String, quoteId: String) throws -> (TripRequest, Flight, Quote) {
        guard let request = request(id: requestId) else {
            throw APIError.server(statusCode: 404, message: "Trip request not found")
        }
        guard request.isActive else {
            throw APIError.server(statusCode: 409, message: "This request is no longer open.")
        }
        guard let quote = request.allQuotes.first(where: { $0.id == quoteId }), quote.isLive() else {
            throw APIError.server(statusCode: 409, message: "This quote has expired or was withdrawn.")
        }
        let aircraft = AircraftSummary(id: quote.aircraft.id, model: quote.aircraft.model, category: quote.aircraft.category,
                                       seats: quote.aircraft.seats, images: quote.aircraft.images ?? [],
                                       amenities: ["Wi-Fi Onboard", "Leather Seating", "Refreshment Service"],
                                       registration: nil)
        let op = OperatorSummary(id: quote.operatorInfo.id, displayName: quote.operatorInfo.displayName,
                                 slug: quote.operatorInfo.displayName.lowercased().replacingOccurrences(of: " ", with: "-"),
                                 verificationStatus: quote.operatorInfo.verificationStatus ?? "VERIFIED",
                                 yearsOperating: nil, flightsCompleted: nil, description: nil, regulator: nil)
        let flight = Flight(id: "local_flight_\(quote.id)", operatorId: op.id, aircraftId: aircraft.id,
                            originId: request.origin.id, destinationId: request.destination.id,
                            departsAt: quote.departsAt, durationMin: quote.durationMin,
                            seatsTotal: max(quote.aircraft.seats, request.passengers),
                            seatsAvailable: max(quote.aircraft.seats, request.passengers),
                            basePriceCents: quote.priceCents, currency: quote.currency,
                            description: "On-demand charter booked through AmblrX.", status: "SOLD_OUT",
                            origin: request.origin, destination: request.destination,
                            aircraft: aircraft, operatorInfo: op)
        return (request, flight, quote)
    }

    func recordAcceptance(requestId: String, quoteId: String, booking: Booking) -> TripRequest? {
        guard let i = state.requests.firstIndex(where: { $0.id == requestId }) else { return nil }
        let quotes = state.requests[i].allQuotes.map { q -> Quote in
            if q.id == quoteId { return q.with(status: .accepted) }
            return q.isPending ? q.with(status: .declined) : q
        }
        state.requests[i] = state.requests[i].with(status: .accepted, quotes: quotes, bookingId: booking.id)
        state.myQuotes = state.myQuotes.map { oq in
            guard oq.tripRequest?.id == requestId else { return oq }
            return OperatorQuote(quote: oq.quote.id == quoteId ? oq.quote.with(status: .accepted)
                                 : (oq.quote.isPending ? oq.quote.with(status: .declined) : oq.quote),
                                 tripRequest: oq.tripRequest)
        }
        upsertBooking(booking)
        save()
        return state.requests[i]
    }

    func bookings() -> [Booking] { state.bookings }

    /// Keeps the shared copy in step when the customer pays for a local hold.
    func syncBooking(_ booking: Booking) {
        guard state.bookings.contains(where: { $0.id == booking.id }) else { return }
        upsertBooking(booking)
        save()
    }

    private func upsertBooking(_ booking: Booking) {
        if let i = state.bookings.firstIndex(where: { $0.id == booking.id }) {
            state.bookings[i] = booking
        } else {
            state.bookings.insert(booking, at: 0)
        }
    }

    // MARK: Operator

    var profile: OperatorProfile? { state.profile }
    var aircraft: [Aircraft] { state.aircraft }
    var flights: [Flight] { state.flights.sorted { $0.departsAt < $1.departsAt } }
    var payouts: PayoutSummary? { state.payouts }

    /// Open requests from the operator's point of view: other quotes hidden, `myQuote` + `quoteCount` filled.
    func operatorInbox(now: Date = Date()) -> [TripRequest] {
        simulate(now: now)
        let mine = Dictionary(state.myQuotes.compactMap { oq in oq.tripRequest.map { ($0.id, oq.quote) } },
                              uniquingKeysWith: { a, b in a.createdAt > b.createdAt ? a : b })
        let fromCustomers = state.requests.map { r -> TripRequest in
            let my = mine[r.id]
            return TripRequest(id: r.id, status: r.status, origin: r.origin, destination: r.destination,
                               departAfter: r.departAfter, departBefore: r.departBefore, passengers: r.passengers,
                               category: r.category, maxPriceCents: r.maxPriceCents, currency: r.currency,
                               notes: r.notes, createdAt: r.createdAt, expiresAt: r.expiresAt, quotes: nil,
                               bookingId: r.bookingId, myQuote: my, quoteCount: r.allQuotes.count)
        }
        let others = state.inbox.map { r in r.with(myQuote: .some(mine[r.id] ?? r.myQuote)) }
        return (fromCustomers + others)
            .map { expireIfNeeded($0, now: now) }
            .filter { $0.isActive }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func operatorQuotes() -> [OperatorQuote] {
        state.myQuotes.sorted { $0.quote.createdAt > $1.quote.createdAt }
    }

    func sendQuote(requestId: String, body: CreateQuoteBody, now: Date = Date()) throws -> Quote {
        guard let profile = state.profile else { throw APIError.server(statusCode: 403, message: "No operator profile") }
        guard let plane = state.aircraft.first(where: { $0.id == body.aircraftId }) else {
            throw APIError.server(statusCode: 400, message: "Pick one of your aircraft.")
        }
        let quote = Quote(id: "local_quote_\(UUID().uuidString.prefix(8).lowercased())", status: QuoteStatus.pending.rawValue,
                          operatorInfo: QuoteOperator(id: profile.id, displayName: profile.displayName,
                                                      verificationStatus: profile.verificationStatus),
                          aircraft: QuoteAircraft(id: plane.id, model: plane.model, category: plane.category,
                                                  seats: plane.seats, images: plane.images),
                          priceCents: body.priceCents, currency: "USD", departsAt: body.departsAt,
                          durationMin: body.durationMin, message: body.message,
                          expiresAt: now.addingTimeInterval(Double(body.expiresInMinutes ?? 120) * 60), createdAt: now)
        var trip: TripRequest?
        if let i = state.requests.firstIndex(where: { $0.id == requestId }) {
            state.requests[i] = state.requests[i].with(status: .quoted, quotes: state.requests[i].allQuotes + [quote])
            trip = state.requests[i]
        } else if let i = state.inbox.firstIndex(where: { $0.id == requestId }) {
            state.inbox[i] = state.inbox[i].with(status: .quoted, myQuote: .some(quote),
                                                 quoteCount: state.inbox[i].effectiveQuoteCount + 1)
            trip = state.inbox[i]
        } else {
            throw APIError.server(statusCode: 404, message: "Trip request not found")
        }
        state.myQuotes.insert(OperatorQuote(quote: quote, tripRequest: trip?.with(quotes: [])), at: 0)
        save()
        return quote
    }

    func withdrawQuote(id: String) throws -> Quote {
        guard let i = state.myQuotes.firstIndex(where: { $0.quote.id == id }) else {
            throw APIError.server(statusCode: 404, message: "Quote not found")
        }
        let withdrawn = state.myQuotes[i].quote.with(status: .withdrawn)
        state.myQuotes[i] = OperatorQuote(quote: withdrawn, tripRequest: state.myQuotes[i].tripRequest)
        state.requests = state.requests.map { r in
            guard r.allQuotes.contains(where: { $0.id == id }) else { return r }
            return r.with(quotes: r.allQuotes.map { $0.id == id ? withdrawn : $0 })
        }
        state.inbox = state.inbox.map { r in r.myQuote?.id == id ? r.with(myQuote: .some(withdrawn)) : r }
        save()
        return withdrawn
    }

    func addFlight(_ body: CreateFlightBody, now: Date = Date()) throws -> Flight {
        guard let profile = state.profile, let plane = state.aircraft.first(where: { $0.id == body.aircraftId }) else {
            throw APIError.server(statusCode: 400, message: "Pick one of your aircraft.")
        }
        guard let origin = airport(body.originIata), let destination = airport(body.destinationIata) else {
            throw APIError.server(statusCode: 400, message: "Pick airports from the list.")
        }
        let seats = body.seatsTotal ?? plane.seats
        let flight = Flight(id: "local_leg_\(UUID().uuidString.prefix(8).lowercased())", operatorId: profile.id,
                            aircraftId: plane.id, originId: origin.id, destinationId: destination.id,
                            departsAt: body.departsAt, durationMin: body.durationMin, seatsTotal: seats,
                            seatsAvailable: seats, basePriceCents: body.basePriceCents, currency: body.currency,
                            description: body.description, status: "PUBLISHED", origin: origin, destination: destination,
                            aircraft: AircraftSummary(id: plane.id, model: plane.model, category: plane.category,
                                                      seats: plane.seats, images: plane.images ?? [],
                                                      amenities: plane.amenities ?? [], registration: plane.registration),
                            operatorInfo: OperatorSummary(id: profile.id, displayName: profile.displayName,
                                                          slug: profile.slug ?? "", verificationStatus: profile.verificationStatus,
                                                          yearsOperating: profile.yearsOperating,
                                                          flightsCompleted: profile.flightsCompleted,
                                                          description: nil, regulator: profile.regulator))
        state.flights.append(flight)
        save()
        return flight
    }

    func addAircraft(_ body: CreateAircraftBody) -> Aircraft {
        let plane = Aircraft(id: "local_aircraft_\(UUID().uuidString.prefix(8).lowercased())", registration: body.registration,
                             model: body.model, category: body.category, seats: body.seats, images: [],
                             amenities: body.amenities ?? [])
        state.aircraft.append(plane)
        save()
        return plane
    }

    // MARK: Tracking

    func updateStatus(booking: Booking, body: StatusUpdateBody, now: Date = Date()) -> Tracking? {
        guard let current = tracking(for: booking, now: now) else { return nil }
        let events = current.events + [TrackingEvent(status: body.status.rawValue, at: now, note: body.note)]
        var position = current.position
        if let lat = body.lat, let lng = body.lng {
            position = TrackingPosition(lat: lat, lng: lng, updatedAt: now)
        } else if body.status == .arrived {
            position = TrackingPosition(lat: current.destination.lat, lng: current.destination.lng, updatedAt: now)
        } else if position == nil {
            position = TrackingPosition(lat: current.origin.lat, lng: current.origin.lng, updatedAt: now)
        }
        let updated = Tracking(bookingId: current.bookingId, reference: current.reference, tripStatus: body.status.rawValue,
                               events: events, position: position,
                               etaMinutes: body.etaMinutes ?? (body.status == .arrived ? 0 : current.etaMinutes),
                               origin: current.origin, destination: current.destination, departsAt: current.departsAt,
                               durationMin: current.durationMin, operatorInfo: current.operatorInfo, aircraft: current.aircraft)
        state.tracking[booking.id] = updated
        save()
        return updated
    }

    /// Operator updates win; otherwise the bundled tracking file; otherwise a time-based simulation
    /// that walks a confirmed booking from Confirmed to Arrived over about six minutes.
    func tracking(for booking: Booking, now: Date = Date()) -> Tracking? {
        if let manual = state.tracking[booking.id] {
            return animate(manual, now: now)
        }
        if let bundled = SampleData.tracking(bookingId: booking.id) {
            return bundled
        }
        guard let flight = booking.flight else { return nil }
        let base = Self.blank(booking: booking, flight: flight)
        guard booking.isConfirmed else { return base }
        let start = booking.createdAt
        let steps: [(TripStatus, TimeInterval, String?)] = [
            (.confirmed, 0, nil),
            (.crewAssigned, 45, "Crew briefed, aircraft fuelled"),
            (.boarding, 90, "Meet your crew at the FBO lounge"),
            (.departed, 150, nil),
            (.arrived, 150 + Self.simulatedFlightSeconds, "Welcome to \(flight.destination.city)"),
        ]
        let events = steps.filter { start.addingTimeInterval($0.1) <= now }
            .map { TrackingEvent(status: $0.0.rawValue, at: start.addingTimeInterval($0.1), note: $0.2) }
        let simulated = Tracking(bookingId: base.bookingId, reference: base.reference, tripStatus: events.last?.status,
                                 events: events, position: nil, etaMinutes: flight.durationMin,
                                 origin: base.origin, destination: base.destination, departsAt: base.departsAt,
                                 durationMin: base.durationMin, operatorInfo: base.operatorInfo, aircraft: base.aircraft)
        return animate(simulated, now: now)
    }

    private static let simulatedFlightSeconds: TimeInterval = 240

    /// Position follows the status: at the origin until departure, along the great circle in flight
    /// (compressed to a few minutes), at the destination once arrived. Explicit operator coordinates win.
    private func animate(_ t: Tracking, now: Date) -> Tracking {
        let status = t.status
        var position = t.position
        var eta = t.etaMinutes
        if status == .departed, let departed = t.event(for: .departed) {
            let manualFix = state.tracking[t.bookingId]?.position.map { $0.updatedAt > departed.at } ?? false
            if !manualFix {
                let progress = min(0.97, max(0, now.timeIntervalSince(departed.at) / Self.simulatedFlightSeconds))
                let p = Geo.interpolate(lat1: t.origin.lat, lng1: t.origin.lng,
                                        lat2: t.destination.lat, lng2: t.destination.lng, t: progress)
                position = TrackingPosition(lat: p.lat, lng: p.lng, updatedAt: now)
                eta = max(1, Int(Double(t.durationMin) * (1 - progress)))
            }
        } else if status == .arrived {
            position = TrackingPosition(lat: t.destination.lat, lng: t.destination.lng,
                                        updatedAt: t.event(for: .arrived)?.at ?? now)
            eta = 0
        } else if position == nil, status != nil {
            position = TrackingPosition(lat: t.origin.lat, lng: t.origin.lng, updatedAt: now)
        }
        return Tracking(bookingId: t.bookingId, reference: t.reference, tripStatus: t.tripStatus, events: t.events,
                        position: position, etaMinutes: eta, origin: t.origin, destination: t.destination,
                        departsAt: t.departsAt, durationMin: t.durationMin, operatorInfo: t.operatorInfo, aircraft: t.aircraft)
    }

    static func blank(booking: Booking, flight: Flight) -> Tracking {
        Tracking(bookingId: booking.id, reference: booking.reference, tripStatus: nil, events: [], position: nil,
                 etaMinutes: nil, origin: flight.origin, destination: flight.destination, departsAt: flight.departsAt,
                 durationMin: flight.durationMin,
                 operatorInfo: TrackingOperator(id: flight.operatorInfo.id, displayName: flight.operatorInfo.displayName),
                 aircraft: TrackingAircraft(model: flight.aircraft.model, registration: flight.aircraft.registration,
                                            category: flight.aircraft.category))
    }

    // MARK: Simulation helpers

    private func airport(_ iata: String) -> Airport? {
        let code = iata.uppercased()
        return SampleData.airports().first { $0.iata == code }
            ?? (state.requests + state.inbox).flatMap { [$0.origin, $0.destination] }.first { $0.iata == code }
    }

    private func expireIfNeeded(_ r: TripRequest, now: Date) -> TripRequest {
        guard r.status == "OPEN" || r.status == "QUOTED", r.expiresAt <= now else { return r }
        return r.with(status: .expired)
    }

    private struct Bot {
        let op: QuoteOperator
        let fleet: [QuoteAircraft]
        let note: String
    }

    private static let bots: [Bot] = [
        Bot(op: QuoteOperator(id: "sample_operator_atlas", displayName: "Atlas Jet Partners", verificationStatus: "VERIFIED"),
            fleet: [QuoteAircraft(id: "sample_ac_atlas_phenom", model: "Phenom 300E", category: "LIGHT_JET", seats: 7, images: []),
                    QuoteAircraft(id: "sample_ac_atlas_praetor", model: "Praetor 600", category: "SUPER_MIDSIZE", seats: 9, images: [])],
            note: "Crew on standby, can depart within 2 hours of confirmation."),
        Bot(op: QuoteOperator(id: "sample_operator_meridian", displayName: "Meridian Air Charter", verificationStatus: "VERIFIED"),
            fleet: [QuoteAircraft(id: "sample_ac_meridian_hawker", model: "Hawker 800XP", category: "MIDSIZE", seats: 8, images: []),
                    QuoteAircraft(id: "sample_ac_meridian_g450", model: "Gulfstream G450", category: "HEAVY_JET", seats: 14, images: [])],
            note: "Repositioning nearby, priced as a partial empty leg."),
        Bot(op: QuoteOperator(id: "sample_operator_northstar", displayName: "Northstar Aviation", verificationStatus: "PENDING"),
            fleet: [QuoteAircraft(id: "sample_ac_northstar_pc12", model: "Pilatus PC-12", category: "TURBOPROP", seats: 8, images: []),
                    QuoteAircraft(id: "sample_ac_northstar_cj3", model: "Citation CJ3+", category: "LIGHT_JET", seats: 6, images: [])],
            note: ""),
    ]

    private static func hourlyRate(_ category: String) -> Double {
        switch category {
        case "TURBOPROP": return 4_600
        case "LIGHT_JET": return 7_200
        case "MIDSIZE": return 9_400
        case "SUPER_MIDSIZE": return 11_200
        case "HEAVY_JET": return 15_800
        default: return 9_000
        }
    }

    /// Adds the scheduled bot quotes that are due for requests created on this device.
    private func simulate(now: Date) {
        var changed = false
        for i in state.requests.indices {
            let r = state.requests[i]
            guard r.id.hasPrefix("local_req_"), r.status == "OPEN" || r.status == "QUOTED", r.expiresAt > now else { continue }
            var quotes = r.allQuotes
            for (n, delay) in Self.botSchedule.enumerated() {
                let id = "local_q_\(r.id)_\(n)"
                let at = r.createdAt.addingTimeInterval(delay)
                guard at <= now, !quotes.contains(where: { $0.id == id }) else { continue }
                if let quote = Self.botQuote(for: r, index: n, id: id, at: at) { quotes.append(quote) }
            }
            if quotes.count != r.allQuotes.count {
                state.requests[i] = r.with(status: quotes.isEmpty ? .open : .quoted, quotes: quotes)
                changed = true
            }
        }
        if changed { save() }
    }

    private static func botQuote(for r: TripRequest, index: Int, id: String, at: Date) -> Quote? {
        let bot = bots[index % bots.count]
        let fitting = bot.fleet.filter { $0.seats >= r.passengers && (r.category == nil || $0.category == r.category) }
        guard let plane = fitting.first ?? bot.fleet.filter({ $0.seats >= r.passengers }).first else { return nil }
        let minutes = Geo.estimatedMinutes(r.origin, r.destination)
        let jitter = [0.92, 1.0, 1.11][index % 3]
        var price = Int((hourlyRate(plane.category) * Double(minutes) / 60.0 * jitter * 1.15 / 50).rounded()) * 5000
        price = max(price, 450_000)
        if let cap = r.maxPriceCents, price > cap { price = Int(Double(cap) * 0.97 / 5000) * 5000 }
        let window = max(0, r.departBefore.timeIntervalSince(r.departAfter))
        let departs = r.departAfter.addingTimeInterval(window * [0.15, 0.4, 0.7][index % 3])
        return Quote(id: id, status: QuoteStatus.pending.rawValue, operatorInfo: bot.op, aircraft: plane,
                     priceCents: price, currency: r.currency, departsAt: departs, durationMin: minutes,
                     message: bot.note.isEmpty ? nil : bot.note, expiresAt: min(r.expiresAt, at.addingTimeInterval(Double(30 + index * 25) * 60)),
                     createdAt: at)
    }
}
