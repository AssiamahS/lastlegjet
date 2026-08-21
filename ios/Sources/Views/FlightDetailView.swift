import SwiftUI

struct FlightDetailView: View {
    let flight: Flight

    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var flights: FlightsStore
    @EnvironmentObject private var bookings: BookingsStore
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var mode: AppMode

    @State private var detail: FlightDetail?
    @State private var passengers = 1
    @State private var isBooking = false
    @State private var bookingError: String?
    @State private var showSignIn = false

    private var current: Flight { detail?.flight ?? flight }
    private var maxPassengers: Int { max(1, current.seatsAvailable) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                gallery
                titleBlock
                statsStrip
                about
                amenities
                operatorCard
                similar
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .screenBackground()
        .safeAreaInset(edge: .bottom) { priceCard }
        .navigationTitle(current.routeCode)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: flight.id) {
            detail = try? await flights.detail(for: flight.id)
            passengers = min(passengers, maxPassengers)
        }
        .sheet(isPresented: $showSignIn) {
            SignInSheet {
                showSignIn = false
                Task { await book() }
            }
        }
        .alert("Booking failed", isPresented: Binding(get: { bookingError != nil }, set: { if !$0 { bookingError = nil } })) {
            Button("OK", role: .cancel) { bookingError = nil }
        } message: {
            Text(bookingError ?? "")
        }
    }

    // MARK: Sections

    private var gallery: some View {
        ZStack {
            LinearGradient(colors: [Brand.inkCard, Brand.gold.opacity(0.35), Brand.ink],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "airplane")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(Brand.cream.opacity(0.9))
                .rotationEffect(.degrees(-20))
            VStack {
                HStack {
                    Spacer()
                    if current.operatorInfo.isVerified { VerifiedPill() }
                }
                Spacer()
                HStack {
                    Pill(text: current.aircraft.categoryLabel, systemImage: "tag", tint: Brand.cream)
                    Spacer()
                }
            }
            .padding(12)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(current.routeTitle)
                .font(.displayTitle)
                .foregroundStyle(Brand.cream)
            Text("\(current.origin.name) to \(current.destination.name)")
                .font(.subheadline)
                .foregroundStyle(Brand.muted)
            Label(current.departsText, systemImage: "calendar")
                .font(.subheadline)
                .foregroundStyle(Brand.gold)
        }
    }

    private var statsStrip: some View {
        HStack(spacing: 0) {
            stat("Aircraft", current.aircraft.model, "airplane")
            divider
            stat("Seats", "\(current.seatsAvailable) of \(current.seatsTotal)", "person.2")
            divider
            stat("Flight time", current.durationText, "clock")
            divider
            stat("Class", current.aircraft.categoryLabel, "star")
        }
        .card(padding: 12)
    }

    private var divider: some View {
        Rectangle().fill(Brand.inkLine).frame(width: 1, height: 36)
    }

    private func stat(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(Brand.gold)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Brand.cream)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Brand.muted)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var about: some View {
        if let description = current.description, !description.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("About this flight")
                Text(description)
                    .font(.body)
                    .foregroundStyle(Brand.cream.opacity(0.9))
            }
        }
    }

    @ViewBuilder
    private var amenities: some View {
        if !current.aircraft.amenities.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Amenities")
                FlowChips(items: current.aircraft.amenities)
            }
        }
    }

    private var operatorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Operator")
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "building.2")
                    .font(.title2)
                    .foregroundStyle(Brand.gold)
                    .frame(width: 44, height: 44)
                    .background(Brand.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 6) {
                    Text(current.operatorInfo.displayName)
                        .font(.headline)
                        .foregroundStyle(Brand.cream)
                    HStack(spacing: 12) {
                        if let years = current.operatorInfo.yearsOperating {
                            Label("\(years) yrs operating", systemImage: "calendar.badge.checkmark")
                        }
                        if let completed = current.operatorInfo.flightsCompleted {
                            Label("\(completed) flights", systemImage: "checkmark.circle")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                    if let regulator = current.operatorInfo.regulator {
                        Text("Regulated by \(regulator)")
                            .font(.caption)
                            .foregroundStyle(Brand.muted)
                    }
                    if current.operatorInfo.isVerified { VerifiedPill() }
                    if let text = current.operatorInfo.description, !text.isEmpty {
                        Text(text)
                            .font(.footnote)
                            .foregroundStyle(Brand.cream.opacity(0.8))
                    }
                }
            }
            .card()
        }
    }

    @ViewBuilder
    private var similar: some View {
        if let similar = detail?.similar, !similar.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Similar flights")
                ForEach(similar) { other in
                    NavigationLink(value: other) {
                        FlightCard(flight: other)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var priceCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Whole aircraft")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                    Text(current.priceText)
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .foregroundStyle(Brand.gold)
                }
                Spacer()
                Stepper(value: $passengers, in: 1...maxPassengers) {
                    Text("\(passengers) pax")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.cream)
                }
                .fixedSize()
            }
            Button {
                Task { await book() }
            } label: {
                if isBooking {
                    ProgressView().tint(Brand.ink)
                } else {
                    Text(current.seatsAvailable > 0 ? "Book This Flight" : "Sold Out")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isBooking || current.seatsAvailable == 0)
            Text("Seats are held for 15 minutes while you pay. Service fee and taxes added at checkout.")
                .font(.caption2)
                .foregroundStyle(Brand.muted)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .background(Brand.inkCard)
        .overlay(alignment: .top) { Rectangle().fill(Brand.inkLine).frame(height: 1) }
    }

    // MARK: Booking

    private func book() async {
        if !mode.isSample && !session.isSignedIn {
            showSignIn = true
            return
        }
        isBooking = true
        defer { isBooking = false }
        do {
            let booking = try await bookings.createBooking(flight: current, passengers: passengers)
            if mode.isSample {
                flights.applyLocalHold(flightId: current.id, passengers: passengers)
            }
            nav.searchPath.append(booking)
        } catch let error as APIError {
            if case .unauthorized = error {
                session.signOut()
                showSignIn = true
            } else {
                bookingError = error.localizedDescription
            }
        } catch {
            bookingError = error.localizedDescription
        }
    }
}

/// Simple wrapping chip layout (rows of chips) without relying on Layout protocol edge cases.
struct FlowChips: View {
    let items: [String]

    var body: some View {
        let rows = chunk(items, size: 2)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        Pill(text: item, systemImage: "checkmark", tint: Brand.cream)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func chunk(_ array: [String], size: Int) -> [[String]] {
        guard size > 0 else { return [array] }
        return stride(from: 0, to: array.count, by: size).map { start in
            Array(array[start..<min(start + size, array.count)])
        }
    }
}

/// Sign-in sheet used when a guest taps "Book This Flight" while connected to the API.
struct SignInSheet: View {
    let onSignedIn: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Sign in to book")
                        .font(.displayTitle)
                        .foregroundStyle(Brand.cream)
                    Text("Your seats are held for 15 minutes once you continue.")
                        .font(.subheadline)
                        .foregroundStyle(Brand.muted)
                    AuthFormView(onSuccess: onSignedIn)
                }
                .padding(16)
            }
            .screenBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
