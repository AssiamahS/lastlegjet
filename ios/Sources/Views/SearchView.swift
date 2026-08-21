import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var flights: FlightsStore
    @EnvironmentObject private var mode: AppMode

    @State private var query = FlightQuery()
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack(path: $nav.searchPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    filters
                    results
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await flights.search(query) }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Flight.self) { flight in
                FlightDetailView(flight: flight)
            }
            .navigationDestination(for: Booking.self) { booking in
                BookingPaymentView(booking: booking)
            }
            .navigationDestination(for: BookingConfirmationRoute.self) { route in
                BookingConfirmationView(booking: route.booking)
            }
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await flights.search(query)
            await openDetailForScreenshotRig()
        }
        .onChange(of: mode.forced) { _, _ in
            Task { await flights.search(query) }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Brand.appName)
                .font(.displayLarge)
                .foregroundStyle(Brand.cream)
            Text("Private jet empty legs at a fraction of charter price.")
                .font(.subheadline)
                .foregroundStyle(Brand.muted)
            if flights.usingSampleData || mode.showsSampleBanner {
                SampleDataBanner(text: flights.usingSampleData && !mode.forced
                                 ? "Sample data — server unreachable" : mode.bannerText)
                    .padding(.top, 4)
            }
        }
        .padding(.top, 8)
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 14) {
            AirportField(title: "From", placeholder: "City or airport (e.g. MIA)", text: $query.from)
            AirportField(title: "To", placeholder: "City or airport (e.g. TEB)", text: $query.to)

            VStack(alignment: .leading, spacing: 8) {
                Text("Aircraft class")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(AircraftCategory.allCases) { category in
                            Chip(label: category.label, isSelected: query.categories.contains(category.rawValue)) {
                                toggle(category)
                            }
                        }
                    }
                }
            }

            HStack {
                Text("Minimum seats")
                    .font(.subheadline)
                    .foregroundStyle(Brand.cream)
                Spacer()
                Stepper(value: $query.minSeats, in: 1...16) {
                    Text("\(query.minSeats)")
                        .font(.headline)
                        .foregroundStyle(Brand.gold)
                        .frame(minWidth: 24)
                }
                .fixedSize()
            }

            Button {
                Task { await flights.search(query) }
            } label: {
                Label("Search Flights", systemImage: "magnifyingglass")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .card()
    }

    @ViewBuilder
    private var results: some View {
        HStack {
            SectionTitle("Available flights")
            if flights.isLoading {
                ProgressView().tint(Brand.gold)
            } else {
                Text("\(flights.flights.count)")
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
            }
        }

        if let error = flights.errorMessage, flights.flights.isEmpty {
            EmptyState(icon: "exclamationmark.triangle", title: "Couldn't load flights", message: error)
        } else if flights.flights.isEmpty && !flights.isLoading {
            EmptyState(icon: "airplane.circle", title: "No flights match",
                       message: "Try clearing the route or aircraft class filters.")
        } else {
            LazyVStack(spacing: 12) {
                ForEach(flights.flights) { flight in
                    NavigationLink(value: flight) {
                        FlightCard(flight: flight)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Helpers

    private func toggle(_ category: AircraftCategory) {
        if query.categories.contains(category.rawValue) {
            query.categories.remove(category.rawValue)
        } else {
            query.categories.insert(category.rawValue)
        }
    }

    /// Screenshot rig: `-uiShotDetail` auto-opens the first flight so CI can capture the detail screen.
    private func openDetailForScreenshotRig() async {
        guard CommandLine.arguments.contains("-uiShotDetail") else { return }
        var attempts = 0
        while flights.flights.isEmpty && attempts < 20 {
            try? await Task.sleep(for: .milliseconds(500))
            attempts += 1
        }
        try? await Task.sleep(for: .seconds(1))
        if let first = flights.flights.first {
            nav.searchPath.append(first)
        }
    }
}

/// Text field with airport autocomplete from `/airports?q=` (or bundled airports when offline).
struct AirportField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    @EnvironmentObject private var flights: FlightsStore
    @FocusState private var focused: Bool
    @State private var suggestions: [Airport] = []
    @State private var suppressLookup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Brand.muted)
            BrandField(title: placeholder, text: $text, capitalization: .characters)
                .focused($focused)
            if focused && !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(suggestions) { airport in
                        Button {
                            suppressLookup = true
                            text = airport.iata
                            suggestions = []
                            focused = false
                        } label: {
                            HStack {
                                Text(airport.iata)
                                    .font(.headline)
                                    .foregroundStyle(Brand.gold)
                                    .frame(width: 48, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(airport.city)
                                        .foregroundStyle(Brand.cream)
                                    Text(airport.name)
                                        .font(.caption)
                                        .foregroundStyle(Brand.muted)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(Brand.inkLine)
                    }
                }
                .background(Brand.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Brand.inkLine))
            }
        }
        .task(id: text) {
            if suppressLookup {
                suppressLookup = false
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
            suggestions = await flights.airports(matching: text)
        }
    }
}
