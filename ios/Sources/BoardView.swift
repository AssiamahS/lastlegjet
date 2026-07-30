import SwiftUI

struct BoardView: View {
    @StateObject private var service = LegsService()
    @State private var selected: Leg?

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.walnut.ignoresSafeArea()
                content
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("LASTLEG")
                            .font(.system(.headline, design: .serif).weight(.bold))
                            .tracking(4)
                            .foregroundStyle(Brand.brass)
                        Text("DEPARTURES · EMPTY LEGS")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(Brand.dim)
                    }
                }
            }
            .toolbarBackground(Brand.walnut, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task {
                // screenshot rig: -uiShotDetail auto-opens the first leg so CI
                // can capture the detail sheet without tap automation
                guard CommandLine.arguments.contains("-uiShotDetail") else { return }
                while service.legs.isEmpty { try? await Task.sleep(for: .seconds(1)) }
                try? await Task.sleep(for: .seconds(1))
                selected = service.legs.first
            }
            .sheet(item: $selected) { leg in
                LegDetailView(leg: leg)
                    .presentationDetents([.medium, .large])
            }
        }
        .task { await service.load() }
    }

    @ViewBuilder
    private var content: some View {
        if service.loading && service.legs.isEmpty {
            ProgressView().tint(Brand.brass)
        } else if let error = service.error, service.legs.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "airplane.circle")
                    .font(.largeTitle)
                    .foregroundStyle(Brand.brass)
                Text(error)
                    .foregroundStyle(Brand.dim)
                Button("Retry") { Task { await service.load() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.brass)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    boardHeader
                    ForEach(service.legs) { leg in
                        Button { selected = leg } label: {
                            LegRow(leg: leg)
                        }
                        .buttonStyle(.plain)
                    }
                    footer
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }
            .refreshable { await service.load() }
        }
    }

    private var boardHeader: some View {
        HStack {
            Text("DATE  ROUTE")
            Spacer()
            Text("SEATS   FARE")
        }
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .tracking(1)
        .foregroundStyle(Brand.dim)
        .padding(.horizontal, 6)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if !service.updated.isEmpty {
                Text("Board updated \(service.updated)")
            }
            Text("Fares set by operators. Seats sell as-is — the jet flies either way.")
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(Brand.dim)
        .multilineTextAlignment(.center)
        .padding(.vertical, 18)
    }
}

struct LegRow: View {
    let leg: Leg

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(leg.date.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Brand.brass)
                Text("\(leg.from) → \(leg.to)")
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(Brand.cream)
                Spacer()
                Text(leg.price)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(Brand.brass)
            }
            HStack {
                Text("\(leg.fromCity) → \(leg.toCity)")
                    .lineLimit(1)
                Spacer()
                Text("\(leg.seats) seats")
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Brand.dim)
        }
        .padding(12)
        .background(Brand.walnutCard, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Brand.brass.opacity(0.15))
        )
    }
}
