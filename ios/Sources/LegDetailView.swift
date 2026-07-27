import SwiftUI

struct LegDetailView: View {
    let leg: Leg
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Brand.walnut.ignoresSafeArea()
            VStack(spacing: 20) {
                Capsule()
                    .fill(Brand.dim.opacity(0.4))
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)

                VStack(spacing: 6) {
                    Text("\(leg.from) → \(leg.to)")
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundStyle(Brand.cream)
                    Text("\(leg.fromCity) to \(leg.toCity)")
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(Brand.dim)
                    Text(leg.price)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(Brand.brass)
                        .padding(.top, 4)
                }

                VStack(spacing: 0) {
                    detailRow("Departs", leg.date)
                    detailRow("Aircraft", leg.aircraft)
                    detailRow("Seats", "\(leg.seats)")
                    detailRow("Operator", leg.operatorName)
                }
                .background(Brand.walnutCard, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)

                Button {
                    let subject = "LastLeg seat request: \(leg.from) → \(leg.to) \(leg.date)"
                    let body = "Leg ID: \(leg.id)\nAircraft: \(leg.aircraft)\nOperator: \(leg.operatorName)\nListed fare: \(leg.price)"
                    var components = URLComponents(string: "mailto:partners@lastleg.example")!
                    components.queryItems = [
                        URLQueryItem(name: "subject", value: subject),
                        URLQueryItem(name: "body", value: body),
                    ]
                    if let url = components.url { openURL(url) }
                } label: {
                    Text("REQUEST SEATS")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .background(Brand.brass, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Brand.walnut)
                .padding(.horizontal, 20)

                Text("The jet is repositioning anyway — this leg flies with or without you. Fares and availability confirmed by the operator.")
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(Brand.dim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Spacer()
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(Brand.dim)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Brand.cream)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider().background(Brand.walnut)
        }
    }
}
