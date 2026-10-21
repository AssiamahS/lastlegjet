import SwiftUI

/// Trips tab: trip requests (Uber mode) and bookings (empty legs + accepted quotes).
struct BookingsView: View {
    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var bookings: BookingsStore
    @EnvironmentObject private var trips: TripsStore
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var mode: AppMode

    private enum Segment: String, CaseIterable, Identifiable {
        case bookings = "Bookings"
        case requests = "Requests"
        var id: String { rawValue }
    }

    @State private var segment: Segment = .bookings

    private var allBookings: [Booking] {
        let own = bookings.bookings
        let extra = trips.previewBookings(excluding: Set(own.map(\.id)))
        return (own + extra).sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack(path: $nav.bookingsPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Trips")
                        .font(.displayLarge)
                        .foregroundStyle(Brand.cream)
                        .padding(.top, 8)
                    Picker("Show", selection: $segment) {
                        ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if trips.usingPreview, let reason = trips.previewReason {
                        SampleDataBanner(text: reason)
                    } else if bookings.usingSampleData || mode.showsSampleBanner {
                        SampleDataBanner(text: bookings.usingSampleData
                                         ? "Sample data — bookings stored on this device" : mode.bannerText)
                    }
                    if segment == .bookings {
                        bookingsList
                    } else {
                        requestsList
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .refreshable { await reload() }
            .navigationTitle("Trips")
            .navigationBarTitleDisplayMode(.inline)
            .appDestinations()
        }
        .task(id: session.isSignedIn) { await reload() }
        .onChange(of: mode.forced) { _, _ in
            Task { await reload() }
        }
    }

    private func reload() async {
        async let a: Void = bookings.load(signedIn: session.isSignedIn)
        async let b: Void = trips.load(signedIn: session.isSignedIn)
        _ = await (a, b)
    }

    @ViewBuilder
    private var bookingsList: some View {
        if bookings.isLoading && allBookings.isEmpty {
            ProgressView().tint(Brand.gold).frame(maxWidth: .infinity).padding(.top, 40)
        } else if let error = bookings.errorMessage, allBookings.isEmpty {
            EmptyState(icon: "exclamationmark.triangle", title: "Couldn't load bookings", message: error)
        } else if allBookings.isEmpty {
            if session.isSignedIn || mode.isSample {
                EmptyState(icon: "airplane", title: "No trips yet",
                           message: "Request a jet from Home or book an empty-leg deal.")
            } else {
                VStack(spacing: 12) {
                    EmptyState(icon: "person.crop.circle.badge.questionmark", title: "Sign in to see trips",
                               message: "Your held and confirmed flights are tied to your account.")
                    Button("Go to Account") { nav.tab = .account }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        } else {
            LazyVStack(spacing: 12) {
                ForEach(allBookings) { booking in
                    NavigationLink(value: booking) {
                        BookingRow(booking: booking)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var requestsList: some View {
        if trips.isLoading && trips.requests.isEmpty {
            ProgressView().tint(Brand.gold).frame(maxWidth: .infinity).padding(.top, 40)
        } else if let error = trips.errorMessage, trips.requests.isEmpty {
            EmptyState(icon: "exclamationmark.triangle", title: "Couldn't load requests", message: error)
        } else if trips.requests.isEmpty {
            VStack(spacing: 12) {
                EmptyState(icon: "paperplane", title: "No requests yet",
                           message: "Tell operators where you're going and they'll quote you live.")
                Button("Where to?") { nav.tab = .home }
                    .buttonStyle(PrimaryButtonStyle())
            }
        } else {
            LazyVStack(spacing: 12) {
                ForEach(trips.requests) { request in
                    NavigationLink(value: TripRequestRoute(requestId: request.id)) {
                        TripRequestRow(request: request)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct BookingRow: View {
    let booking: Booking

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(booking.flight?.routeCode ?? booking.flightId)
                        .font(.system(.title3, design: .serif).weight(.semibold))
                        .foregroundStyle(Brand.cream)
                    if let flight = booking.flight {
                        Text(flight.cityPair)
                            .font(.subheadline)
                            .foregroundStyle(Brand.muted)
                    }
                }
                Spacer()
                StatusBadge(status: booking.status)
            }
            HStack {
                Text(booking.reference)
                    .font(.caption.monospaced())
                    .foregroundStyle(Brand.gold)
                Spacer()
                if let flight = booking.flight {
                    Text(flight.departsText)
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                }
            }
            HStack {
                Text("\(booking.passengers) pax")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                if booking.isConfirmed {
                    Label("Track", systemImage: "location.north.line")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.bronzeLight)
                }
                Spacer()
                Text(booking.totalText)
                    .font(.headline)
                    .foregroundStyle(Brand.cream)
            }
            if booking.isHeld {
                Text(booking.holdExpiresAt > Date()
                     ? "Held until \(DateText.time(booking.holdExpiresAt, timezone: nil)) — tap to pay"
                     : "Hold expired")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(booking.holdExpiresAt > Date() ? Brand.gold : Brand.danger)
            }
        }
        .card()
    }
}
