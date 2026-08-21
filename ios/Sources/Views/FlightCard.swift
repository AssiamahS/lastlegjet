import SwiftUI

struct FlightCard: View {
    let flight: Flight

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(flight.routeCode)
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .foregroundStyle(Brand.cream)
                    Text(flight.cityPair)
                        .font(.subheadline)
                        .foregroundStyle(Brand.muted)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("From")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                    Text(flight.priceText)
                        .font(.headline)
                        .foregroundStyle(Brand.gold)
                }
            }

            HStack(spacing: 14) {
                detail("airplane", flight.aircraft.model)
                detail("person.2", "\(flight.seatsAvailable) seats")
                detail("clock", flight.durationText)
            }

            HStack {
                Label(flight.departsText, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                Spacer()
                if flight.operatorInfo.isVerified {
                    VerifiedPill()
                }
            }
        }
        .card()
    }

    private func detail(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(Brand.cream.opacity(0.85))
        .lineLimit(1)
    }
}
