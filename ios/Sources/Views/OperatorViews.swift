import SwiftUI

enum OperatorSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case requests = "Requests"
    case legs = "My Legs"
    case trips = "Trips"
    case fleet = "Fleet"
    case payouts = "Payouts"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.50percent"
        case .requests: return "tray.full"
        case .legs: return "airplane.departure"
        case .trips: return "point.topleft.down.to.point.bottomright.curvepath"
        case .fleet: return "airplane"
        case .payouts: return "banknote"
        }
    }
}

/// Operator tab: dashboard, live request inbox + quoting, empty legs, trips with status updates, fleet, payouts.
struct OperatorRootView: View {
    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var ops: OperatorStore
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var mode: AppMode
    @AppStorage("operator.section") private var sectionRaw = OperatorSection.dashboard.rawValue

    private var section: OperatorSection { OperatorSection(rawValue: sectionRaw) ?? .dashboard }

    var body: some View {
        NavigationStack(path: $nav.operatorPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    sectionPicker
                    if let error = ops.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Brand.danger)
                    }
                    switch section {
                    case .dashboard: OperatorDashboard(select: select)
                    case .requests: RequestsInbox()
                    case .legs: MyLegsSection()
                    case .trips: OperatorTripsSection()
                    case .fleet: FleetSection()
                    case .payouts: PayoutsSection()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .refreshable { await ops.load(user: session.user) }
            .navigationTitle("Operator")
            .navigationBarTitleDisplayMode(.inline)
            .appDestinations()
        }
        .task(id: session.user?.id) { await ops.load(user: session.user) }
        .task(id: sectionRaw) {
            // keep the inbox and trip statuses fresh while those sections are open
            guard section == .requests || section == .dashboard else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(ops.usingPreview ? 4 : 10))
                if Task.isCancelled { break }
                await ops.loadUberMode()
            }
        }
        .onChange(of: mode.forced) { _, _ in
            Task { await ops.load(user: session.user) }
        }
    }

    private func select(_ s: OperatorSection) {
        withAnimation(.snappy) { sectionRaw = s.rawValue }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ops.profile?.displayName ?? "Operator")
                .font(.displayLarge)
                .foregroundStyle(Brand.cream)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            HStack(spacing: 8) {
                if ops.profile?.isVerified == true { VerifiedPill() }
                if let regulator = ops.profile?.regulator {
                    Pill(text: regulator + (ops.profile?.aocNumber.map { " · \($0)" } ?? ""), systemImage: "doc.text", tint: Brand.cream)
                }
                if ops.isLoading { ProgressView().tint(Brand.gold).scaleEffect(0.8) }
            }
            if let reason = ops.previewReason {
                SampleDataBanner(text: reason)
            }
        }
        .padding(.top, 8)
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(OperatorSection.allCases) { s in
                    Button {
                        select(s)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: s.systemImage)
                            Text(s.rawValue)
                            if s == .requests, ops.openRequestCount > 0 {
                                Text("\(ops.openRequestCount)")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Brand.danger, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(s == section ? Brand.ink : Brand.cream)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            if s == section {
                                Capsule().fill(Brand.bronzeGradient)
                            } else {
                                Capsule().fill(Brand.inkCard)
                            }
                        }
                        .overlay(Capsule().strokeBorder(s == section ? Brand.bronze : Brand.inkLine))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Dashboard

struct OperatorDashboard: View {
    let select: (OperatorSection) -> Void
    @EnvironmentObject private var ops: OperatorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                Button { select(.trips) } label: {
                    StatTile(title: "Today's trips", value: "\(ops.todaysTrips.count)", systemImage: "calendar")
                }
                Button { select(.requests) } label: {
                    StatTile(title: "Open requests", value: "\(ops.openRequestCount)", systemImage: "tray.full")
                }
                Button { select(.payouts) } label: {
                    StatTile(title: "Pending earnings", value: ops.payouts?.pendingText ?? "—", systemImage: "hourglass")
                }
                Button { select(.payouts) } label: {
                    StatTile(title: "Paid out", value: ops.payouts?.paidText ?? "—", systemImage: "banknote")
                }
                Button { select(.legs) } label: {
                    StatTile(title: "Live empty legs", value: "\(ops.flights.filter { $0.status == "PUBLISHED" }.count)",
                             systemImage: "airplane.departure")
                }
                Button { select(.fleet) } label: {
                    StatTile(title: "Aircraft", value: "\(ops.aircraft.count)", systemImage: "airplane")
                }
            }
            .buttonStyle(.plain)

            SectionTitle(ops.todaysTrips.isEmpty ? "Next trips" : "Today")
            let trips = ops.todaysTrips.isEmpty ? Array(ops.upcomingTrips.prefix(3)) : ops.todaysTrips
            if trips.isEmpty {
                Text("No confirmed trips yet. Quote open requests to win some.")
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
            } else {
                ForEach(trips) { booking in
                    Button { select(.trips) } label: {
                        OperatorTripSummary(booking: booking, tracking: ops.trackingByBooking[booking.id])
                    }
                    .buttonStyle(.plain)
                    .task { await ops.loadTracking(for: booking) }
                }
            }

            SectionTitle("Newest requests")
            let newest = ops.requests.filter(\.isActive).prefix(3)
            if newest.isEmpty {
                Text("No open requests right now.")
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
            } else {
                ForEach(Array(newest)) { request in
                    Button { select(.requests) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(request.routeCode)
                                    .font(.headline)
                                    .foregroundStyle(Brand.cream)
                                Text("\(request.passengers) pax · \(request.categoryLabel)")
                                    .font(.caption)
                                    .foregroundStyle(Brand.muted)
                            }
                            Spacer()
                            if let mine = request.myQuote, mine.isPending {
                                Pill(text: "Quoted \(mine.priceText)", tint: Brand.success)
                            } else {
                                Pill(text: "Quote", systemImage: "paperplane")
                            }
                        }
                        .card(padding: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct OperatorTripSummary: View {
    let booking: Booking
    let tracking: Tracking?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(booking.flight?.routeCode ?? booking.reference)
                    .font(.headline)
                    .foregroundStyle(Brand.cream)
                Text("\(booking.reference) · \(booking.flight?.departsText ?? "")")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
            }
            Spacer()
            Pill(text: tracking?.statusLabel ?? "Scheduled", tint: Brand.bronzeLight)
        }
        .card(padding: 12)
    }
}

// MARK: - Requests inbox

struct RequestsInbox: View {
    @EnvironmentObject private var ops: OperatorStore
    @State private var quoting: TripRequest?
    @State private var errorMessage: String?
    @State private var busyQuoteId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let open = ops.requests.filter(\.isActive)
            if open.isEmpty {
                EmptyState(icon: "tray", title: "Inbox zero", message: "New trip requests from travellers land here in real time.")
            } else {
                ForEach(open) { request in
                    RequestInboxCard(request: request, isBusy: busyQuoteId == request.myQuote?.id) {
                        quoting = request
                    } onWithdraw: { quote in
                        Task { await withdraw(quote) }
                    }
                }
            }
            if !ops.quotes.isEmpty {
                SectionTitle("My quotes")
                    .padding(.top, 8)
                ForEach(ops.quotes) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.tripRequest?.routeCode ?? "Trip request")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Brand.cream)
                            Text("\(item.quote.aircraft.model) · \(item.quote.priceText)")
                                .font(.caption)
                                .foregroundStyle(Brand.muted)
                        }
                        Spacer()
                        Pill(text: item.quote.quoteStatus?.label ?? item.quote.status,
                             tint: item.quote.status == "ACCEPTED" ? Brand.success : (item.quote.isPending ? Brand.bronze : Brand.muted))
                    }
                    .card(padding: 12)
                }
            }
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Brand.danger)
            }
        }
        .sheet(item: $quoting) { request in
            SendQuoteSheet(request: request)
        }
    }

    private func withdraw(_ quote: Quote) async {
        busyQuoteId = quote.id
        defer { busyQuoteId = nil }
        do {
            try await ops.withdraw(quoteId: quote.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct RequestInboxCard: View {
    let request: TripRequest
    var isBusy = false
    let onQuote: () -> Void
    let onWithdraw: (Quote) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(request.routeCode)
                        .font(.system(.title3, design: .serif).weight(.semibold))
                        .foregroundStyle(Brand.cream)
                    Text(request.cityPair)
                        .font(.subheadline)
                        .foregroundStyle(Brand.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(request.effectiveQuoteCount) quote\(request.effectiveQuoteCount == 1 ? "" : "s")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.bronzeLight)
                    CountdownText(date: request.expiresAt, prefix: "")
                        .font(.caption2)
                        .foregroundStyle(Brand.muted)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Label(request.windowText, systemImage: "calendar")
                Label("\(request.passengers) passengers · \(request.categoryLabel)", systemImage: "person.2")
                if let max = request.maxPriceText {
                    Label("Budget up to \(max)", systemImage: "dollarsign.circle")
                }
                if let notes = request.notes, !notes.isEmpty {
                    Label(notes, systemImage: "text.bubble")
                }
            }
            .font(.caption)
            .foregroundStyle(Brand.cream.opacity(0.85))
            if let mine = request.myQuote, mine.isPending {
                HStack {
                    Label("Your quote \(mine.priceText) · \(mine.aircraft.model)", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.success)
                    Spacer()
                    Button(isBusy ? "Withdrawing…" : "Withdraw") { onWithdraw(mine) }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.danger)
                        .disabled(isBusy)
                }
            } else {
                Button(action: onQuote) {
                    Label(request.myQuote == nil ? "Send Quote" : "Quote Again", systemImage: "paperplane.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .card()
    }
}

struct SendQuoteSheet: View {
    let request: TripRequest

    @EnvironmentObject private var ops: OperatorStore
    @Environment(\.dismiss) private var dismiss
    @State private var aircraftId = ""
    @State private var price = ""
    @State private var departsAt = Date()
    @State private var durationMin = 60
    @State private var message = ""
    @State private var expiresIn = 120
    @State private var isSending = false
    @State private var errorMessage: String?

    private var fitting: [Aircraft] {
        // the API rejects aircraft with fewer seats than passengers (API_CONTRACT_DEVIATIONS.md #5)
        ops.aircraft.filter { $0.seats >= request.passengers }
    }

    private var priceCents: Int? {
        guard let dollars = Int(price.filter(\.isNumber)), dollars > 0 else { return nil }
        return dollars * 100
    }

    private var window: ClosedRange<Date> {
        // departsAt must be in the future and inside the request window
        let start = max(request.departAfter, Date().addingTimeInterval(10 * 60))
        return start...max(start, request.departBefore)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(request.cityPair)
                            .font(.displayHeadline)
                            .foregroundStyle(Brand.cream)
                        Text("\(request.passengers) pax · \(request.categoryLabel)\(request.maxPriceText.map { " · budget \($0)" } ?? "")")
                            .font(.caption)
                            .foregroundStyle(Brand.muted)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Aircraft").font(.caption.weight(.semibold)).foregroundStyle(Brand.muted)
                        if fitting.isEmpty {
                            Text("No aircraft with \(request.passengers)+ seats. Add one in Fleet first.")
                                .font(.subheadline)
                                .foregroundStyle(Brand.danger)
                        }
                        ForEach(fitting) { plane in
                            Button {
                                aircraftId = plane.id
                            } label: {
                                HStack {
                                    Image(systemName: aircraftId == plane.id ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(Brand.bronze)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(plane.title).foregroundStyle(Brand.cream)
                                        Text("\(plane.categoryLabel) · \(plane.seats) seats")
                                            .font(.caption)
                                            .foregroundStyle(Brand.muted)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(Brand.inkCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    BrandField(title: "Price (USD, whole aircraft)", text: $price, keyboard: .numberPad)
                    DatePicker("Departs", selection: $departsAt, in: window, displayedComponents: [.date, .hourAndMinute])
                        .foregroundStyle(Brand.cream)
                    Stepper(value: $durationMin, in: 15...(18 * 60), step: 5) {
                        HStack {
                            Text("Flight time").foregroundStyle(Brand.cream)
                            Spacer()
                            Text(DurationText.text(minutes: durationMin)).foregroundStyle(Brand.gold)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quote valid for").font(.caption.weight(.semibold)).foregroundStyle(Brand.muted)
                        Picker("Valid for", selection: $expiresIn) {
                            Text("30 min").tag(30)
                            Text("1 h").tag(60)
                            Text("2 h").tag(120)
                            Text("4 h").tag(240)
                        }
                        .pickerStyle(.segmented)
                    }
                    BrandField(title: "Message to the traveller (optional)", text: $message, capitalization: .sentences)
                    if let errorMessage = errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(Brand.danger)
                    }
                    Button {
                        Task { await send() }
                    } label: {
                        if isSending { ProgressView().tint(Brand.ink) } else { Text("Send Quote") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(aircraftId.isEmpty || priceCents == nil || isSending)
                }
                .padding(16)
            }
            .tint(Brand.bronze)
            .screenBackground()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Send quote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .onAppear {
            aircraftId = fitting.first?.id ?? ""
            departsAt = window.lowerBound
            durationMin = Geo.estimatedMinutes(request.origin, request.destination)
            if let max = request.maxPriceCents { price = String(Int(Double(max) * 0.9 / 100)) }
        }
    }

    private func send() async {
        guard let cents = priceCents else { return }
        isSending = true
        defer { isSending = false }
        let note = message.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await ops.sendQuote(requestId: request.id,
                                    body: CreateQuoteBody(aircraftId: aircraftId, priceCents: cents, departsAt: departsAt,
                                                          durationMin: durationMin, message: note.isEmpty ? nil : note,
                                                          expiresInMinutes: expiresIn))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - My legs

struct MyLegsSection: View {
    @EnvironmentObject private var ops: OperatorStore
    @State private var showPost = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                showPost = true
            } label: {
                Label("Post Empty Leg", systemImage: "plus.circle.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            if ops.flights.isEmpty {
                EmptyState(icon: "airplane.departure", title: "No legs posted",
                           message: "Repositioning flights you post here show up in Deals for travellers.")
            } else {
                ForEach(ops.flights) { flight in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(flight.routeCode)
                                    .font(.system(.title3, design: .serif).weight(.semibold))
                                    .foregroundStyle(Brand.cream)
                                Text(flight.departsText)
                                    .font(.caption)
                                    .foregroundStyle(Brand.muted)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(flight.priceText)
                                    .font(.headline)
                                    .bronzeFill()
                                Pill(text: flight.status.capitalized,
                                     tint: flight.status == "PUBLISHED" ? Brand.success : Brand.muted)
                            }
                        }
                        Text("\(flight.aircraft.model) · \(flight.seatsAvailable)/\(flight.seatsTotal) seats · \(flight.durationText)")
                            .font(.caption)
                            .foregroundStyle(Brand.cream.opacity(0.8))
                    }
                    .card()
                }
            }
        }
        .sheet(isPresented: $showPost) { PostLegSheet() }
    }
}

struct PostLegSheet: View {
    @EnvironmentObject private var ops: OperatorStore
    @Environment(\.dismiss) private var dismiss
    @State private var aircraftId = ""
    @State private var from: Airport?
    @State private var to: Airport?
    @State private var picking: AirportSlot?
    @State private var departsAt = TripDraft.roundedHour(hoursFromNow: 24)
    @State private var durationMin = 120
    @State private var price = ""
    @State private var seats = 6
    @State private var details = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var plane: Aircraft? { ops.aircraft.first { $0.id == aircraftId } }
    private var priceCents: Int? {
        guard let dollars = Int(price.filter(\.isNumber)), dollars > 0 else { return nil }
        return dollars * 100
    }
    private var canSave: Bool {
        plane != nil && from != nil && to != nil && from?.iata != to?.iata && priceCents != nil && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Aircraft", selection: $aircraftId) {
                        ForEach(ops.aircraft) { Text($0.title).tag($0.id) }
                    }
                    .pickerStyle(.menu)
                    .tint(Brand.bronze)
                    airportRow("From", from, .from)
                    airportRow("To", to, .to)
                    DatePicker("Departs", selection: $departsAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .foregroundStyle(Brand.cream)
                    Stepper(value: $durationMin, in: 15...(18 * 60), step: 5) {
                        HStack {
                            Text("Flight time").foregroundStyle(Brand.cream)
                            Spacer()
                            Text(DurationText.text(minutes: durationMin)).foregroundStyle(Brand.gold)
                        }
                    }
                    Stepper(value: $seats, in: 1...(plane?.seats ?? 19)) {
                        HStack {
                            Text("Seats").foregroundStyle(Brand.cream)
                            Spacer()
                            Text("\(seats)").foregroundStyle(Brand.gold)
                        }
                    }
                    BrandField(title: "Price (USD, whole aircraft)", text: $price, keyboard: .numberPad)
                    BrandField(title: "Description (optional)", text: $details, capitalization: .sentences)
                    if let errorMessage = errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(Brand.danger)
                    }
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView().tint(Brand.ink) } else { Text("Publish Leg") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSave)
                }
                .padding(16)
            }
            .tint(Brand.bronze)
            .screenBackground()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Post empty leg")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(item: $picking) { slot in
                AirportPickerSheet(title: slot == .from ? "From" : "To", offerNearest: slot == .from) { airport in
                    if slot == .from { from = airport } else { to = airport }
                    if let a = from, let b = to { durationMin = Geo.estimatedMinutes(a, b) }
                }
            }
        }
        .onAppear {
            aircraftId = ops.aircraft.first?.id ?? ""
            seats = ops.aircraft.first?.seats ?? 6
        }
        .onChange(of: aircraftId) { _, _ in seats = plane?.seats ?? seats }
    }

    private func airportRow(_ label: String, _ airport: Airport?, _ slot: AirportSlot) -> some View {
        Button {
            picking = slot
        } label: {
            HStack {
                Text(label).foregroundStyle(Brand.muted).frame(width: 44, alignment: .leading)
                if let airport = airport {
                    Text(airport.iata).font(.headline).bronzeFill()
                    Text(airport.city).foregroundStyle(Brand.cream)
                } else {
                    Text("Choose airport").foregroundStyle(Brand.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Brand.muted)
            }
            .padding(12)
            .background(Brand.inkCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func save() async {
        guard let plane = plane, let from = from, let to = to, let cents = priceCents else { return }
        isSaving = true
        defer { isSaving = false }
        let text = details.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await ops.postLeg(CreateFlightBody(aircraftId: plane.id, originIata: from.iata, destinationIata: to.iata,
                                                   departsAt: departsAt, durationMin: durationMin, basePriceCents: cents,
                                                   currency: "USD", seatsTotal: seats,
                                                   description: text.isEmpty ? nil : text))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Trips (status updates)

struct OperatorTripsSection: View {
    @EnvironmentObject private var ops: OperatorStore

    private var sorted: [Booking] {
        ops.bookings.sorted { ($0.flight?.departsAt ?? .distantFuture) < ($1.flight?.departsAt ?? .distantFuture) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if sorted.isEmpty {
                EmptyState(icon: "person.2", title: "No bookings yet",
                           message: "Bookings on your legs and accepted quotes appear here.")
            } else {
                Text("Status updates share this phone's location as the aircraft position when Location is allowed.")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                ForEach(sorted) { booking in
                    OperatorTripCard(booking: booking)
                }
            }
        }
    }
}

struct OperatorTripCard: View {
    let booking: Booking

    @EnvironmentObject private var ops: OperatorStore
    @State private var isSending = false
    @State private var result: String?
    @State private var errorMessage: String?

    private var tracking: Tracking? { ops.trackingByBooking[booking.id] }
    private var nextStatus: TripStatus? {
        guard let status = tracking?.status else { return .confirmed }
        return status.next
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(booking.flight?.routeCode ?? booking.reference)
                        .font(.system(.title3, design: .serif).weight(.semibold))
                        .foregroundStyle(Brand.cream)
                    Text("\(booking.reference) · \(booking.customer?.fullName ?? "Traveller") · \(booking.passengers) pax")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                    if let flight = booking.flight {
                        Text(flight.departsText)
                            .font(.caption)
                            .foregroundStyle(Brand.muted)
                    }
                }
                Spacer()
                StatusBadge(status: booking.status)
            }
            if booking.isConfirmed {
                HStack {
                    Label(tracking?.statusLabel ?? "Scheduled", systemImage: tracking?.status?.systemImage ?? "calendar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.bronzeLight)
                    Spacer()
                    Menu {
                        ForEach(TripStatus.allCases) { status in
                            Button(status.label, systemImage: status.systemImage) {
                                Task { await advance(to: status) }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(Brand.cream)
                    }
                    .disabled(isSending)
                }
                if let next = nextStatus, tracking?.status != .cancelled {
                    Button {
                        Task { await advance(to: next) }
                    } label: {
                        if isSending {
                            ProgressView().tint(Brand.ink)
                        } else {
                            Label("Mark \(next.label)", systemImage: next.systemImage)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isSending)
                } else if tracking?.status == .arrived {
                    Label("Trip complete", systemImage: "flag.checkered")
                        .font(.subheadline)
                        .foregroundStyle(Brand.success)
                }
                if let result = result {
                    Text(result).font(.caption).foregroundStyle(Brand.muted)
                }
            } else if booking.isHeld {
                Text("Awaiting the traveller's payment.")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
            }
            if let errorMessage = errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(Brand.danger)
            }
        }
        .card()
        .task(id: booking.id) { await ops.loadTracking(for: booking) }
    }

    private func advance(to status: TripStatus) async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        let fix = await LocationProvider.shared.currentLocation(timeout: 5)
        let coords = fix.map { (lat: $0.coordinate.latitude, lng: $0.coordinate.longitude) }
        let eta: Int? = {
            guard let flight = booking.flight else { return nil }
            switch status {
            case .departed: return flight.durationMin
            case .arrived: return 0
            default: return nil
            }
        }()
        do {
            try await ops.advance(booking: booking, to: status, location: coords, etaMinutes: eta, note: nil)
            if let c = coords {
                result = "\(status.label) sent with position \(String(format: "%.3f, %.3f", c.lat, c.lng))"
            } else {
                result = "\(status.label) sent (no location)"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Fleet

struct FleetSection: View {
    @EnvironmentObject private var ops: OperatorStore
    @State private var showAdd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                showAdd = true
            } label: {
                Label("Add Aircraft", systemImage: "plus.circle.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            ForEach(ops.aircraft) { plane in
                HStack(spacing: 12) {
                    Image(systemName: "airplane")
                        .font(.title3)
                        .bronzeFill()
                        .frame(width: 44, height: 44)
                        .background(Brand.bronze.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(plane.model)
                            .font(.headline)
                            .foregroundStyle(Brand.cream)
                        Text("\(plane.categoryLabel) · \(plane.seats) seats")
                            .font(.caption)
                            .foregroundStyle(Brand.muted)
                    }
                    Spacer()
                    if let reg = plane.registration {
                        Text(reg)
                            .font(.caption.monospaced())
                            .foregroundStyle(Brand.gold)
                    }
                }
                .card(padding: 12)
            }
        }
        .sheet(isPresented: $showAdd) { AddAircraftSheet() }
    }
}

struct AddAircraftSheet: View {
    @EnvironmentObject private var ops: OperatorStore
    @Environment(\.dismiss) private var dismiss
    @State private var model = ""
    @State private var category = AircraftCategory.lightJet.rawValue
    @State private var seats = 6
    @State private var registration = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BrandField(title: "Model (e.g. Citation CJ3+)", text: $model, capitalization: .words)
                    Picker("Category", selection: $category) {
                        ForEach(AircraftCategory.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.menu)
                    Stepper(value: $seats, in: 1...50) {
                        HStack {
                            Text("Seats").foregroundStyle(Brand.cream)
                            Spacer()
                            Text("\(seats)").foregroundStyle(Brand.gold)
                        }
                    }
                    BrandField(title: "Registration (e.g. N123AX)", text: $registration, capitalization: .characters)
                    if let errorMessage = errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(Brand.danger)
                    }
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView().tint(Brand.ink) } else { Text("Add Aircraft") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.trimmingCharacters(in: .whitespaces).count < 2 || isSaving)
                }
                .padding(16)
            }
            .tint(Brand.bronze)
            .screenBackground()
            .navigationTitle("Add aircraft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let reg = registration.trimmingCharacters(in: .whitespaces).uppercased()
        do {
            try await ops.addAircraft(CreateAircraftBody(model: model.trimmingCharacters(in: .whitespaces), category: category,
                                                         seats: seats, registration: reg.isEmpty ? nil : reg, amenities: nil))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Payouts

struct PayoutsSection: View {
    @EnvironmentObject private var ops: OperatorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let summary = ops.payouts {
                HStack(spacing: 12) {
                    StatTile(title: "Pending (\(summary.pendingBookings) booking\(summary.pendingBookings == 1 ? "" : "s"))",
                             value: summary.pendingText, systemImage: "hourglass")
                    StatTile(title: "Paid out", value: summary.paidText, systemImage: "checkmark.circle")
                }
                HStack {
                    Label(summary.payoutsEnabled ? "Payouts enabled" : "Payouts not enabled",
                          systemImage: summary.payoutsEnabled ? "checkmark.seal.fill" : "exclamationmark.triangle")
                        .foregroundStyle(summary.payoutsEnabled ? Brand.success : Brand.danger)
                    Spacer()
                    Pill(text: summary.mode == "mock" ? "Test mode" : "Stripe", tint: Brand.cream)
                }
                .font(.subheadline)
                SectionTitle("History")
                if summary.payouts.isEmpty {
                    Text("No payouts yet. Net earnings are paid out after each trip completes.")
                        .font(.subheadline)
                        .foregroundStyle(Brand.muted)
                } else {
                    ForEach(summary.payouts) { payout in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(payout.amountText)
                                    .font(.headline)
                                    .foregroundStyle(Brand.cream)
                                Text(DateText.short(payout.paidAt ?? payout.createdAt))
                                    .font(.caption)
                                    .foregroundStyle(Brand.muted)
                            }
                            Spacer()
                            Pill(text: payout.status.capitalized, tint: payout.status == "PAID" ? Brand.success : Brand.bronze)
                        }
                        .card(padding: 12)
                    }
                }
            } else {
                EmptyState(icon: "banknote", title: "No payout data", message: "Pull to refresh.")
            }
        }
    }
}
