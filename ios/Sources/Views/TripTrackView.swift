import SwiftUI
import MapKit

/// Live trip: map with route + plane, status timeline, ETA. Polls `GET /bookings/:id/track`.
struct TripTrackView: View {
    let booking: Booking

    @EnvironmentObject private var trips: TripsStore
    @EnvironmentObject private var bookings: BookingsStore
    @EnvironmentObject private var nav: AppNavigation
    @State private var tracking: Tracking?
    @State private var camera: MapCameraPosition = .automatic
    @State private var framed = false
    @State private var loadError: String?

    /// Latest copy (the payment screen may have confirmed it since this view was pushed).
    private var current: Booking { bookings.bookings.first { $0.id == booking.id } ?? booking }

    private var origin: Airport? { tracking?.origin ?? current.flight?.origin }
    private var destination: Airport? { tracking?.destination ?? current.flight?.destination }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                map
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Brand.inkLine))
                statusHeader
                if current.isHeld {
                    Button("Complete Payment") { nav.push(current) }
                        .buttonStyle(PrimaryButtonStyle())
                }
                timeline
                details
                if let loadError = loadError {
                    Text(loadError)
                        .font(.caption)
                        .foregroundStyle(Brand.danger)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(current.reference)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: booking.id) { await poll() }
    }

    // MARK: Map

    private var map: some View {
        Map(position: $camera) {
            if let origin = origin {
                Annotation(origin.iata, coordinate: origin.coordinate, anchor: .center) {
                    AirportPin(code: origin.iata, filled: false)
                }
            }
            if let destination = destination {
                Annotation(destination.iata, coordinate: destination.coordinate, anchor: .center) {
                    AirportPin(code: destination.iata, filled: true)
                }
            }
            if let origin = origin, let destination = destination {
                MapPolyline(coordinates: [origin.coordinate, destination.coordinate], contourStyle: .geodesic)
                    .stroke(Brand.bronze.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 6]))
                if let position = tracking?.position {
                    let here = CLLocationCoordinate2D(latitude: position.lat, longitude: position.lng)
                    MapPolyline(coordinates: [origin.coordinate, here], contourStyle: .geodesic)
                        .stroke(Brand.bronzeLight, lineWidth: 4)
                    Annotation("Aircraft", coordinate: here, anchor: .center) {
                        PlaneMarker(heading: Geo.bearing(lat1: position.lat, lng1: position.lng,
                                                         lat2: destination.lat, lng2: destination.lng))
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
    }

    // MARK: Sections

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(tracking?.statusLabel ?? (current.isHeld ? "Awaiting payment" : "Scheduled"))
                    .font(.displayTitle)
                    .foregroundStyle(Brand.cream)
                Spacer()
                if let eta = tracking?.etaMinutes, tracking?.status != .arrived, tracking?.status != .cancelled {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(eta == 0 ? "Now" : DurationText.text(minutes: eta))
                            .font(.headline)
                            .bronzeFill()
                        Text(tracking?.status == .departed ? "to landing" : "flight time")
                            .font(.caption2)
                            .foregroundStyle(Brand.muted)
                    }
                }
            }
            if let origin = origin, let destination = destination {
                Text("\(origin.city) → \(destination.city)")
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
            }
            if let note = tracking?.events.last?.note, !note.isEmpty {
                Label(note, systemImage: "text.bubble")
                    .font(.footnote)
                    .foregroundStyle(Brand.bronzeLight)
            }
            if let updated = tracking?.position?.updatedAt {
                Text("Position updated \(updated.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(Brand.muted)
            }
        }
    }

    private var timeline: some View {
        let status = tracking?.status
        let reachedIndex: Int = {
            guard let status = status, let i = TripStatus.progression.firstIndex(of: status) else { return -1 }
            return i
        }()
        return VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Status")
                .padding(.bottom, 10)
            if status == .cancelled {
                Label("Trip cancelled by the operator", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(Brand.danger)
                    .padding(.bottom, 8)
            }
            TimelineRow(title: "Scheduled", systemImage: "calendar", time: current.flight?.departsAt,
                        timeLabel: "Departs", note: nil, reached: true, isCurrent: status == nil, isLast: false)
            ForEach(Array(TripStatus.progression.enumerated()), id: \.element) { index, step in
                let event = tracking?.event(for: step)
                TimelineRow(title: step.label, systemImage: step.systemImage, time: event?.at, timeLabel: nil,
                            note: event?.note, reached: index <= reachedIndex, isCurrent: index == reachedIndex,
                            isLast: index == TripStatus.progression.count - 1)
            }
        }
        .card()
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledRow(label: "Reference", value: current.reference)
            if let t = tracking {
                LabeledRow(label: "Aircraft", value: [t.aircraft.model, t.aircraft.registration].compactMap { $0 }.joined(separator: " · "))
                LabeledRow(label: "Operator", value: t.operatorInfo.displayName)
                LabeledRow(label: "Departs", value: DateText.departure(t.departsAt, timezone: t.origin.timezone))
                LabeledRow(label: "Flight time", value: DurationText.text(minutes: t.durationMin))
            } else if let flight = current.flight {
                LabeledRow(label: "Aircraft", value: flight.aircraft.model)
                LabeledRow(label: "Operator", value: flight.operatorInfo.displayName)
                LabeledRow(label: "Departs", value: flight.departsText)
            }
            LabeledRow(label: "Passengers", value: "\(current.passengers)")
            Divider().overlay(Brand.inkLine)
            LabeledRow(label: current.isConfirmed ? "Total paid" : "Total", value: current.totalText, emphasize: true)
        }
        .card()
    }

    // MARK: Polling

    private func poll() async {
        while !Task.isCancelled {
            do {
                tracking = try await trips.track(current)
                loadError = nil
            } catch {
                loadError = error.localizedDescription
            }
            if !framed, let origin = origin, let destination = destination {
                framed = true
                camera = .region(routeRegion(origin, destination, sheetBias: 0))
            }
            let previewing = trips.usingPreview || current.id.hasPrefix("local_") || current.id.hasPrefix("sample_")
            try? await Task.sleep(for: .seconds(previewing ? 3 : 10))
        }
    }
}

struct PlaneMarker: View {
    /// Degrees clockwise from north.
    let heading: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(Brand.ink.opacity(0.85))
                .frame(width: 38, height: 38)
                .overlay(Circle().strokeBorder(Brand.bronze, lineWidth: 2))
            Image(systemName: "airplane")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Brand.bronzeGradient)
                .rotationEffect(.degrees(heading - 90))
        }
        .shadow(color: .black.opacity(0.5), radius: 6)
    }
}

struct TimelineRow: View {
    let title: String
    let systemImage: String
    let time: Date?
    let timeLabel: String?
    let note: String?
    let reached: Bool
    let isCurrent: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(reached ? AnyShapeStyle(Brand.bronzeGradient) : AnyShapeStyle(Brand.inkCard))
                        .frame(width: 26, height: 26)
                        .overlay(Circle().strokeBorder(reached ? Brand.bronze : Brand.inkLine, lineWidth: 1.5))
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(reached ? Brand.ink : Brand.muted)
                }
                if !isLast {
                    Rectangle()
                        .fill(reached ? Brand.bronze.opacity(0.6) : Brand.inkLine)
                        .frame(width: 2)
                        .frame(minHeight: 22)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(isCurrent ? .bold : .regular))
                        .foregroundStyle(reached ? Brand.cream : Brand.muted)
                    if isCurrent {
                        Pill(text: "NOW", tint: Brand.bronzeLight)
                    }
                    Spacer()
                    if let time = time {
                        Text((timeLabel.map { "\($0) " } ?? "") + DateText.time(time, timezone: nil))
                            .font(.caption)
                            .foregroundStyle(Brand.muted)
                    }
                }
                if let note = note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                }
            }
            .padding(.bottom, isLast ? 0 : 12)
        }
    }
}
