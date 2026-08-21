import SwiftUI

struct BookingConfirmationView: View {
    let booking: Booking

    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var mode: AppMode

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                StepIndicator(current: 3)

                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Brand.gold)
                    Text("You're booked")
                        .font(.displayLarge)
                        .foregroundStyle(Brand.cream)
                    Text("Booking reference")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                    Text(booking.reference)
                        .font(.system(.title, design: .monospaced).weight(.bold))
                        .foregroundStyle(Brand.gold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Brand.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    StatusBadge(status: booking.status)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

                if let flight = booking.flight {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(flight.routeTitle)
                            .font(.displayHeadline)
                            .foregroundStyle(Brand.cream)
                        LabeledRow(label: "Departs", value: flight.departsText)
                        LabeledRow(label: "Aircraft", value: flight.aircraft.model)
                        LabeledRow(label: "Operator", value: flight.operatorInfo.displayName)
                        LabeledRow(label: "Passengers", value: "\(booking.passengers)")
                        Divider().overlay(Brand.inkLine)
                        LabeledRow(label: "Total paid", value: booking.totalText, emphasize: true)
                    }
                    .card()
                }

                Text(mode.isSample
                     ? "This booking was created locally in sample mode — nothing was sent to the server."
                     : "A confirmation email is on its way. The operator will contact you with boarding details.")
                    .font(.footnote)
                    .foregroundStyle(Brand.muted)
                    .multilineTextAlignment(.center)

                Button("View My Bookings") { nav.showBookings() }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Back to Search") { nav.resetToSearch() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Confirmation")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }
}
