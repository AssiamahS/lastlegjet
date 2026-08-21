import SwiftUI

struct BookingsView: View {
    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var bookings: BookingsStore
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var mode: AppMode

    var body: some View {
        NavigationStack(path: $nav.bookingsPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("My Bookings")
                        .font(.displayLarge)
                        .foregroundStyle(Brand.cream)
                        .padding(.top, 8)
                    if bookings.usingSampleData || mode.showsSampleBanner {
                        SampleDataBanner(text: bookings.usingSampleData
                                         ? "Sample data — bookings stored on this device" : mode.bannerText)
                    }
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .refreshable { await bookings.load(signedIn: session.isSignedIn) }
            .navigationTitle("Bookings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Booking.self) { booking in
                if booking.isHeld {
                    BookingPaymentView(booking: booking)
                } else {
                    BookingConfirmationView(booking: booking)
                }
            }
            .navigationDestination(for: BookingConfirmationRoute.self) { route in
                BookingConfirmationView(booking: route.booking)
            }
        }
        .task(id: session.isSignedIn) {
            await bookings.load(signedIn: session.isSignedIn)
        }
        .onChange(of: mode.forced) { _, _ in
            Task { await bookings.load(signedIn: session.isSignedIn) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if bookings.isLoading && bookings.bookings.isEmpty {
            ProgressView().tint(Brand.gold).frame(maxWidth: .infinity).padding(.top, 40)
        } else if let error = bookings.errorMessage, bookings.bookings.isEmpty {
            EmptyState(icon: "exclamationmark.triangle", title: "Couldn't load bookings", message: error)
        } else if bookings.bookings.isEmpty {
            if session.isSignedIn || mode.isSample {
                EmptyState(icon: "ticket", title: "No bookings yet",
                           message: "Book an empty leg from the Search tab and it will show up here.")
            } else {
                VStack(spacing: 12) {
                    EmptyState(icon: "person.crop.circle.badge.questionmark", title: "Sign in to see bookings",
                               message: "Your held and confirmed flights are tied to your account.")
                    Button("Go to Account") { nav.tab = .account }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        } else {
            LazyVStack(spacing: 12) {
                ForEach(bookings.bookings) { booking in
                    NavigationLink(value: booking) {
                        BookingRow(booking: booking)
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
