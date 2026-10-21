import SwiftUI

/// Live state of one trip request: searching animation, incoming quote cards, accept / cancel.
struct QuotesBoard: View {
    let request: TripRequest
    var acceptingQuoteId: String?
    var maxHeight: CGFloat = .infinity
    let onAccept: (Quote) -> Void
    let onCancel: () -> Void
    let onOpenBooking: (Booking) -> Void

    @EnvironmentObject private var bookings: BookingsStore
    @EnvironmentObject private var trips: TripsStore

    private var booking: Booking? {
        guard let id = request.bookingId else { return nil }
        return bookings.bookings.first { $0.id == id }
            ?? trips.previewBookings(excluding: []).first { $0.id == id }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let live = request.liveQuotes(at: now)
        switch request.requestStatus {
        case .accepted:
            VStack(alignment: .leading, spacing: 10) {
                Label("Quote accepted", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(Brand.success)
                if let booking = booking {
                    Text(booking.isHeld ? "Aircraft held for you. Pay to confirm." : "Booking \(booking.reference) is \(booking.statusLabel.lowercased()).")
                        .font(.subheadline)
                        .foregroundStyle(Brand.muted)
                    Button(booking.isHeld ? "Complete Payment" : "Track Trip") { onOpenBooking(booking) }
                        .buttonStyle(PrimaryButtonStyle())
                } else {
                    Text("Find the booking under Trips.")
                        .font(.subheadline)
                        .foregroundStyle(Brand.muted)
                }
            }
        case .cancelled, .expired:
            EmptyState(icon: request.requestStatus == .cancelled ? "xmark.circle" : "hourglass",
                       title: request.statusLabel,
                       message: "This request is closed. Start a new one from Home.")
        default:
            VStack(alignment: .leading, spacing: 12) {
                if live.isEmpty {
                    SearchingIndicator(origin: request.origin.city, quoteCount: request.allQuotes.count)
                } else {
                    HStack {
                        Text("\(live.count) quote\(live.count == 1 ? "" : "s")")
                            .font(.headline)
                            .foregroundStyle(Brand.cream)
                        Text("· from \(live[0].priceText)")
                            .font(.subheadline)
                            .foregroundStyle(Brand.muted)
                        Spacer()
                        ProgressView().tint(Brand.bronze).scaleEffect(0.8)
                    }
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(live) { quote in
                                QuoteCard(quote: quote, passengers: request.passengers,
                                          isAccepting: acceptingQuoteId == quote.id) {
                                    onAccept(quote)
                                }
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .animation(.snappy, value: live.map(\.id))
                    }
                    .frame(maxHeight: maxHeight)
                }
                HStack {
                    CountdownText(date: request.expiresAt, prefix: "Request open for ")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                    Spacer()
                    Button("Cancel request", role: .destructive, action: onCancel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.danger)
                }
            }
        }
    }
}

/// Pulsing radar while operators look at the request.
struct SearchingIndicator: View {
    let origin: String
    var quoteCount = 0
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Brand.bronze.opacity(0.5), lineWidth: 2)
                    .frame(width: 46, height: 46)
                    .scaleEffect(pulse ? 1.35 : 0.8)
                    .opacity(pulse ? 0 : 1)
                Circle()
                    .fill(Brand.bronzeGradient)
                    .frame(width: 30, height: 30)
                Image(systemName: "airplane")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Brand.ink)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text("Finding operators…")
                    .font(.headline)
                    .foregroundStyle(Brand.cream)
                Text(quoteCount > 0 ? "Earlier quotes expired — waiting for fresh ones"
                     : "Sent to verified operators near \(origin). Quotes appear here live.")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
            }
            Spacer(minLength: 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

struct QuoteCard: View {
    let quote: Quote
    let passengers: Int
    var isAccepting = false
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(quote.operatorInfo.displayName)
                            .font(.headline)
                            .foregroundStyle(Brand.cream)
                        if quote.operatorInfo.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(Brand.bronze)
                                .accessibilityLabel("Verified operator")
                        }
                    }
                    Text("\(quote.aircraft.model) · \(quote.aircraft.categoryLabel) · \(quote.aircraft.seats) seats")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                }
                Spacer()
                Text(quote.priceText)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .bronzeFill()
            }
            HStack(spacing: 14) {
                Label(DateText.departure(quote.departsAt, timezone: nil), systemImage: "calendar")
                Label(quote.durationText, systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(Brand.cream.opacity(0.85))
            if let message = quote.message, !message.isEmpty {
                Text("“\(message)”")
                    .font(.footnote)
                    .italic()
                    .foregroundStyle(Brand.cream.opacity(0.75))
            }
            HStack {
                CountdownText(date: quote.expiresAt)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(quote.expiresAt.timeIntervalSinceNow < 600 ? Brand.danger : Brand.bronzeLight)
                Spacer()
                Button(action: onAccept) {
                    if isAccepting {
                        ProgressView().tint(Brand.ink)
                    } else {
                        Text("Accept")
                    }
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Brand.ink)
                .padding(.horizontal, 22)
                .padding(.vertical, 9)
                .background(Brand.bronzeGradient, in: Capsule())
                .disabled(isAccepting)
            }
        }
        .card(padding: 14)
    }
}

/// Trips → a request: same live board, full screen.
struct TripRequestDetailView: View {
    let requestId: String

    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var trips: TripsStore
    @EnvironmentObject private var bookings: BookingsStore
    @State private var acceptingQuoteId: String?
    @State private var errorMessage: String?

    private var request: TripRequest? { trips.requests.first { $0.id == requestId } }

    var body: some View {
        ScrollView {
            if let request = request {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(request.cityPair)
                            .font(.displayTitle)
                            .foregroundStyle(Brand.cream)
                        Text(request.windowText)
                            .font(.subheadline)
                            .foregroundStyle(Brand.muted)
                        HStack(spacing: 8) {
                            Pill(text: request.statusLabel)
                            Pill(text: "\(request.passengers) pax", systemImage: "person.2", tint: Brand.cream)
                            Pill(text: request.categoryLabel, systemImage: "airplane", tint: Brand.cream)
                        }
                        if let max = request.maxPriceText {
                            Text("Max price \(max)")
                                .font(.caption)
                                .foregroundStyle(Brand.muted)
                        }
                        if let notes = request.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.footnote)
                                .foregroundStyle(Brand.cream.opacity(0.8))
                        }
                    }
                    QuotesBoard(request: request, acceptingQuoteId: acceptingQuoteId) { quote in
                        Task { await accept(request, quote) }
                    } onCancel: {
                        Task {
                            do { _ = try await trips.cancel(id: request.id) } catch { errorMessage = error.localizedDescription }
                        }
                    } onOpenBooking: { booking in
                        nav.push(booking)
                    }
                }
                .padding(16)
            } else {
                EmptyState(icon: "questionmark.circle", title: "Request not found", message: "Pull to refresh Trips.")
            }
        }
        .screenBackground()
        .navigationTitle(request?.routeCode ?? "Request")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: requestId) {
            while !Task.isCancelled {
                _ = try? await trips.refresh(id: requestId)
                try? await Task.sleep(for: .seconds(trips.usingPreview ? 2 : 5))
            }
        }
        .alert("Couldn't complete that", isPresented: Binding(get: { errorMessage != nil },
                                                               set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func accept(_ request: TripRequest, _ quote: Quote) async {
        acceptingQuoteId = quote.id
        defer { acceptingQuoteId = nil }
        do {
            let booking = try await trips.accept(request: request, quote: quote, bookings: bookings)
            nav.push(booking)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TripRequestRow: View {
    let request: TripRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                Pill(text: request.statusLabel.uppercased(),
                     tint: request.isActive ? Brand.bronze : (request.status == "ACCEPTED" ? Brand.success : Brand.muted))
            }
            HStack {
                Label(DateText.departure(request.departAfter, timezone: request.origin.timezone), systemImage: "calendar")
                Spacer()
                let live = request.liveQuotes().count
                Text(request.isActive ? (live == 0 ? "Waiting for quotes" : "\(live) live quote\(live == 1 ? "" : "s")") : "\(request.passengers) pax")
            }
            .font(.caption)
            .foregroundStyle(Brand.muted)
        }
        .card()
    }
}
