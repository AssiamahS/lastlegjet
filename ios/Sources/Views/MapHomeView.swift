import SwiftUI
import MapKit

extension Airport {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

/// Region that frames two airports with room for the bottom sheet underneath.
func routeRegion(_ a: Airport, _ b: Airport, sheetBias: Double = 0.35) -> MKCoordinateRegion {
    let latSpan = max(abs(a.lat - b.lat) * 1.9, 3)
    let lngSpan = max(abs(a.lng - b.lng) * 1.6, 3)
    let center = CLLocationCoordinate2D(latitude: (a.lat + b.lat) / 2 - latSpan * sheetBias,
                                        longitude: (a.lng + b.lng) / 2)
    return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: min(latSpan * (1 + sheetBias), 150),
                                                                   longitudeDelta: min(lngSpan, 300)))
}

/// What the customer is filling in on the "Where to?" sheet.
struct TripDraft {
    var from: Airport?
    var to: Airport?
    var departAfter: Date = TripDraft.roundedHour(hoursFromNow: 3)
    var departBefore: Date = TripDraft.roundedHour(hoursFromNow: 27)
    var passengers = 2
    var category: String?
    var maxPrice = ""
    var notes = ""

    static func roundedHour(hoursFromNow: Int) -> Date {
        let date = Date().addingTimeInterval(TimeInterval(hoursFromNow) * 3600)
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: date)) ?? date
    }

    var maxPriceCents: Int? {
        let digits = maxPrice.filter(\.isNumber)
        guard let dollars = Int(digits), dollars > 0 else { return nil }
        return dollars * 100
    }

    var isComplete: Bool {
        guard let from = from, let to = to else { return false }
        return from.iata != to.iata && departBefore > departAfter && departBefore > Date()
    }

    var body: CreateTripRequestBody? {
        guard isComplete, let from = from, let to = to else { return nil }
        let note = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return CreateTripRequestBody(originIata: from.iata, destinationIata: to.iata,
                                     departAfter: departAfter, departBefore: departBefore,
                                     passengers: passengers, category: category,
                                     maxPriceCents: maxPriceCents, notes: note.isEmpty ? nil : note)
    }
}

enum AirportSlot: String, Identifiable {
    case from, to
    var id: String { rawValue }
}

/// Home: full-screen map with an Uber-style bottom sheet — Where to? → request → live quotes → accept.
struct MapHomeView: View {
    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var trips: TripsStore
    @EnvironmentObject private var bookings: BookingsStore
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var mode: AppMode

    private enum Stage { case collapsed, form }

    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 30, longitude: -92),
        span: MKCoordinateSpan(latitudeDelta: 45, longitudeDelta: 60)))
    @State private var draft = TripDraft()
    @State private var stage: Stage = .collapsed
    @AppStorage("home.activeRequestId") private var activeRequestId = ""
    @State private var picking: AirportSlot?
    @State private var showSignIn = false
    @State private var isSubmitting = false
    @State private var acceptingQuoteId: String?
    @State private var errorMessage: String?
    @State private var locating = false

    private var activeRequest: TripRequest? {
        activeRequestId.isEmpty ? nil : trips.requests.first { $0.id == activeRequestId }
    }

    private var shownOrigin: Airport? { activeRequest?.origin ?? draft.from }
    private var shownDestination: Airport? { activeRequest?.destination ?? draft.to }

    var body: some View {
        NavigationStack(path: $nav.homePath) {
            ZStack(alignment: .top) {
                map
                    .ignoresSafeArea()
                topBar
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { sheet }
            .toolbar(.hidden, for: .navigationBar)
            .appDestinations()
        }
        .sheet(item: $picking) { slot in
            AirportPickerSheet(title: slot == .from ? "Departing from" : "Flying to",
                               offerNearest: slot == .from) { airport in
                if slot == .from { draft.from = airport } else { draft.to = airport }
                frameRoute()
            }
        }
        .sheet(isPresented: $showSignIn) {
            SignInSheet {
                showSignIn = false
                Task { await submit() }
            }
        }
        .task(id: session.isSignedIn) {
            await trips.load(signedIn: session.isSignedIn)
            resumeActiveRequest()
        }
        .task(id: activeRequestId) { await pollActiveRequest() }
        .onChange(of: mode.forced) { _, _ in
            activeRequestId = ""
            Task { await trips.load(signedIn: session.isSignedIn) }
        }
        .alert("Couldn't complete that", isPresented: Binding(get: { errorMessage != nil },
                                                               set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Map

    private var map: some View {
        Map(position: $camera) {
            if let origin = shownOrigin {
                Annotation(origin.iata, coordinate: origin.coordinate, anchor: .center) {
                    AirportPin(code: origin.iata, filled: false)
                }
            }
            if let destination = shownDestination {
                Annotation(destination.iata, coordinate: destination.coordinate, anchor: .center) {
                    AirportPin(code: destination.iata, filled: true)
                }
            }
            if let origin = shownOrigin, let destination = shownDestination {
                MapPolyline(coordinates: [origin.coordinate, destination.coordinate], contourStyle: .geodesic)
                    .stroke(Brand.bronze, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 6]))
            }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
        }
    }

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack {
                BrandLogo(height: 26)
                Spacer()
                Button {
                    Task { await useNearestAirport() }
                } label: {
                    Image(systemName: locating ? "location.fill" : "location")
                        .font(.headline)
                        .foregroundStyle(Brand.cream)
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Use nearest airport")
            }
            if trips.usingPreview, let reason = trips.previewReason {
                SampleDataBanner(text: reason)
            } else if mode.showsSampleBanner {
                SampleDataBanner(text: mode.bannerText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background(LinearGradient(colors: [Brand.ink.opacity(0.85), Brand.ink.opacity(0)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    // MARK: Bottom sheet

    private var sheet: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Brand.inkLine)
                .frame(width: 40, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 10)
            Group {
                if let request = activeRequest {
                    activePanel(request)
                } else if stage == .form {
                    formPanel
                } else {
                    collapsedPanel
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(Brand.ink)
                .shadow(color: .black.opacity(0.5), radius: 18, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
        .animation(.snappy, value: stage)
        .animation(.snappy, value: activeRequestId)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
        if let name = session.user?.firstName, !name.isEmpty { return "\(part), \(name)" }
        return part
    }

    private var collapsedPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(greeting)
                .font(.displayHeadline)
                .foregroundStyle(Brand.cream)
            Button {
                stage = .form
                if draft.from == nil || draft.to == nil { picking = draft.from == nil ? .from : .to }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.headline)
                        .bronzeFill()
                    Text("Where to?")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Brand.cream)
                    Spacer()
                    Label("Now", systemImage: "clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.cream)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Brand.ink, in: Capsule())
                }
                .padding(16)
                .background(Brand.inkCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Brand.inkLine))
            }
            .buttonStyle(.plain)
            recentRequests
        }
    }

    @ViewBuilder
    private var recentRequests: some View {
        let recent = trips.requests.filter(\.isActive).prefix(3)
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Open requests")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.muted)
                ForEach(Array(recent)) { request in
                    Button {
                        activeRequestId = request.id
                        frame(request.origin, request.destination)
                    } label: {
                        HStack {
                            Image(systemName: "airplane.circle")
                                .bronzeFill()
                            Text(request.routeCode)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Brand.cream)
                            Text(request.statusLabel)
                                .font(.caption)
                                .foregroundStyle(Brand.muted)
                            Spacer()
                            if !request.liveQuotes().isEmpty {
                                Pill(text: "\(request.liveQuotes().count) quotes", tint: Brand.bronzeLight)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Brand.muted)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var formPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Request a jet")
                        .font(.displayHeadline)
                        .foregroundStyle(Brand.cream)
                    Spacer()
                    Button("Close") { stage = .collapsed }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.muted)
                }
                routePicker
                VStack(spacing: 10) {
                    DatePicker("Earliest departure", selection: $draft.departAfter, in: Date()...,
                               displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Latest departure", selection: $draft.departBefore, in: draft.departAfter...,
                               displayedComponents: [.date, .hourAndMinute])
                }
                .font(.subheadline)
                .foregroundStyle(Brand.cream)
                .tint(Brand.bronze)
                HStack {
                    Text("Passengers")
                        .font(.subheadline)
                        .foregroundStyle(Brand.cream)
                    Spacer()
                    Stepper(value: $draft.passengers, in: 1...19) {
                        Text("\(draft.passengers)")
                            .font(.headline)
                            .foregroundStyle(Brand.gold)
                            .frame(minWidth: 24)
                    }
                    .fixedSize()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Aircraft")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.muted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Chip(label: "Any", isSelected: draft.category == nil) { draft.category = nil }
                            ForEach(AircraftCategory.allCases) { category in
                                Chip(label: category.label, isSelected: draft.category == category.rawValue) {
                                    draft.category = category.rawValue
                                }
                            }
                        }
                    }
                }
                HStack(spacing: 12) {
                    BrandField(title: "Max price (USD, optional)", text: $draft.maxPrice, keyboard: .numberPad)
                }
                BrandField(title: "Notes for operators (optional)", text: $draft.notes, capitalization: .sentences)
                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting {
                        ProgressView().tint(Brand.ink)
                    } else {
                        Label("Request Quotes", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!draft.isComplete || isSubmitting)
                Text("Verified operators send firm quotes. Accept one and pay to lock the aircraft.")
                    .font(.caption2)
                    .foregroundStyle(Brand.muted)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxHeight: 470)
    }

    private var routePicker: some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                Circle().strokeBorder(Brand.bronze, lineWidth: 2).frame(width: 10, height: 10)
                Rectangle().fill(Brand.inkLine).frame(width: 2, height: 28)
                Image(systemName: "square.fill").font(.system(size: 9)).bronzeFill()
            }
            VStack(spacing: 8) {
                airportButton(draft.from, placeholder: "From", slot: .from)
                airportButton(draft.to, placeholder: "Where to?", slot: .to)
            }
            Button {
                let previousFrom = draft.from
                draft.from = draft.to
                draft.to = previousFrom
                frameRoute()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundStyle(Brand.cream)
                    .frame(width: 36, height: 36)
                    .background(Brand.inkCard, in: Circle())
            }
            .accessibilityLabel("Swap airports")
        }
    }

    private func airportButton(_ airport: Airport?, placeholder: String, slot: AirportSlot) -> some View {
        Button {
            picking = slot
        } label: {
            HStack {
                if let airport = airport {
                    Text(airport.iata)
                        .font(.headline)
                        .bronzeFill()
                    Text(airport.city)
                        .foregroundStyle(Brand.cream)
                        .lineLimit(1)
                } else {
                    Text(placeholder)
                        .foregroundStyle(Brand.muted)
                }
                Spacer()
            }
            .padding(12)
            .background(Brand.inkCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func activePanel(_ request: TripRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.routeCode)
                        .font(.displayHeadline)
                        .foregroundStyle(Brand.cream)
                    Text("\(request.passengers) pax · \(request.categoryLabel)")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                }
                Spacer()
                Button {
                    activeRequestId = ""
                    stage = .collapsed
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Brand.muted)
                        .frame(width: 32, height: 32)
                        .background(Brand.inkCard, in: Circle())
                }
                .accessibilityLabel("Hide request")
            }
            QuotesBoard(request: request, acceptingQuoteId: acceptingQuoteId, maxHeight: 360) { quote in
                Task { await accept(request, quote) }
            } onCancel: {
                Task { await cancel(request) }
            } onOpenBooking: { booking in
                nav.homePath.append(booking)
            }
        }
    }

    // MARK: Actions

    private func resumeActiveRequest() {
        if !activeRequestId.isEmpty, activeRequest == nil { activeRequestId = "" }
        if let request = activeRequest { frame(request.origin, request.destination) }
    }

    private func pollActiveRequest() async {
        guard !activeRequestId.isEmpty else { return }
        let id = activeRequestId
        while !Task.isCancelled {
            if let request = try? await trips.refresh(id: id), !request.isActive, request.status != "ACCEPTED" {
                break
            }
            try? await Task.sleep(for: .seconds(trips.usingPreview ? 2 : 4))
        }
    }

    private func submit() async {
        guard let body = draft.body else { return }
        if !mode.isSample && !session.isSignedIn {
            showSignIn = true
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let request = try await trips.create(body, signedIn: session.isSignedIn)
            activeRequestId = request.id
            stage = .collapsed
            frame(request.origin, request.destination)
            Task { await PushRegistrar.shared.requestAndRegister() }
        } catch {
            errorMessage = describe(error)
        }
    }

    private func accept(_ request: TripRequest, _ quote: Quote) async {
        acceptingQuoteId = quote.id
        defer { acceptingQuoteId = nil }
        do {
            let booking = try await trips.accept(request: request, quote: quote, bookings: bookings)
            nav.homePath.append(booking)
        } catch {
            errorMessage = describe(error)
        }
    }

    private func cancel(_ request: TripRequest) async {
        do {
            _ = try await trips.cancel(id: request.id)
            activeRequestId = ""
        } catch {
            errorMessage = describe(error)
        }
    }

    private func useNearestAirport() async {
        locating = true
        defer { locating = false }
        guard let here = await LocationProvider.shared.currentLocation() else {
            errorMessage = "Location is off for AmblrX. Pick your departure airport from the list instead."
            return
        }
        let nearest = SampleData.nearestAirport(lat: here.coordinate.latitude, lng: here.coordinate.longitude)
        draft.from = nearest
        stage = .form
        withAnimation {
            camera = .region(MKCoordinateRegion(center: here.coordinate,
                                                span: MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 6)))
        }
    }

    private func frameRoute() {
        if let from = draft.from, let to = draft.to {
            frame(from, to)
        } else if let one = draft.from ?? draft.to {
            withAnimation {
                camera = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: one.lat - 4, longitude: one.lng),
                                                    span: MKCoordinateSpan(latitudeDelta: 14, longitudeDelta: 14)))
            }
        }
    }

    private func frame(_ a: Airport, _ b: Airport) {
        withAnimation(.easeInOut(duration: 0.8)) {
            camera = .region(routeRegion(a, b))
        }
    }

    private func describe(_ error: Error) -> String {
        if case APIError.server(let code, _) = error, code == 403 {
            return "This account can't request trips. Switch to the traveller account in Account → Switch role."
        }
        return error.localizedDescription
    }
}

/// Map marker for an airport: hollow ring for origin, filled bronze for destination.
struct AirportPin: View {
    let code: String
    var filled: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(code)
                .font(.caption.weight(.bold))
                .foregroundStyle(filled ? Brand.ink : Brand.cream)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    if filled {
                        Capsule().fill(Brand.bronzeGradient)
                    } else {
                        Capsule().fill(Brand.ink)
                    }
                }
                .overlay(Capsule().strokeBorder(Brand.bronze, lineWidth: 1))
            Circle()
                .fill(filled ? Brand.bronze : Brand.ink)
                .overlay(Circle().strokeBorder(Brand.bronze, lineWidth: 2))
                .frame(width: 12, height: 12)
        }
    }
}

/// Airport search: bundled list when empty, `/airports?q=` (or bundled match) while typing.
struct AirportPickerSheet: View {
    let title: String
    var offerNearest = false
    let onPick: (Airport) -> Void

    @EnvironmentObject private var flights: FlightsStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Airport] = []
    @State private var locating = false

    var body: some View {
        NavigationStack {
            List {
                if offerNearest && query.isEmpty {
                    Button {
                        Task { await pickNearest() }
                    } label: {
                        Label(locating ? "Finding you…" : "Nearest airport to me", systemImage: "location.fill")
                            .foregroundStyle(Brand.gold)
                    }
                    .listRowBackground(Brand.inkCard)
                }
                ForEach(results) { airport in
                    Button {
                        onPick(airport)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Text(airport.iata)
                                .font(.headline)
                                .bronzeFill()
                                .frame(width: 48, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(airport.city)
                                    .foregroundStyle(Brand.cream)
                                Text(airport.name)
                                    .font(.caption)
                                    .foregroundStyle(Brand.muted)
                            }
                            Spacer()
                            Text(airport.country)
                                .font(.caption2)
                                .foregroundStyle(Brand.muted)
                        }
                    }
                    .listRowBackground(Brand.inkCard)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Brand.ink)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "City, airport or code")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: query) {
                let q = query.trimmingCharacters(in: .whitespaces)
                if q.count < 2 {
                    results = SampleData.airports().sorted { $0.city < $1.city }
                    return
                }
                try? await Task.sleep(for: .milliseconds(200))
                if Task.isCancelled { return }
                results = await flights.airports(matching: q)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func pickNearest() async {
        locating = true
        defer { locating = false }
        guard let here = await LocationProvider.shared.currentLocation() else { return }
        let nearest = SampleData.nearestAirport(lat: here.coordinate.latitude, lng: here.coordinate.longitude)
        if let nearest = nearest {
            onPick(nearest)
            dismiss()
        }
    }
}
