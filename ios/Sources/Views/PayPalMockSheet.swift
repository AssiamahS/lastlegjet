import SwiftUI
import SafariServices

/// Stand-in for PayPal's approval screen when the PAYPAL rail runs in mock mode.
/// Approve → `POST /paypal/capture` → confirmation. Nothing is opened in the browser.
struct PayPalMockSheet: View {
    let booking: Booking
    let payerEmail: String
    let onConfirmed: (Booking) -> Void

    @EnvironmentObject private var bookings: BookingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var isCapturing = false
    @State private var errorMessage: String?

    private static let paypalBlue = Color(red: 0x00 / 255.0, green: 0x30 / 255.0, blue: 0x87 / 255.0)
    private static let paypalYellow = Color(red: 0xFF / 255.0, green: 0xC4 / 255.0, blue: 0x39 / 255.0)

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PAY LAST LEG JET")
                        .font(.caption2.weight(.semibold))
                        .tracking(1)
                        .foregroundStyle(Brand.muted)
                    Text(booking.totalText)
                        .font(.system(.largeTitle, design: .serif).weight(.semibold))
                        .foregroundStyle(Brand.cream)
                    Text("Ref \(booking.reference)")
                        .font(.caption.monospaced())
                        .foregroundStyle(Brand.muted)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Paying as")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                    Text(payerEmail)
                        .foregroundStyle(Brand.cream)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Brand.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text("This sheet simulates PayPal's approval screen. No real money moves. Approving captures the mock order and confirms your booking.")
                    .font(.footnote)
                    .foregroundStyle(Brand.muted)

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Brand.danger)
                }

                Button {
                    Task { await approve() }
                } label: {
                    if isCapturing {
                        ProgressView().tint(Self.paypalBlue)
                    } else {
                        Text("Approve payment")
                    }
                }
                .buttonStyle(PayPalButtonStyle())
                .disabled(isCapturing)

                Button("Cancel and return") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isCapturing)
            }
            .padding(20)
            Spacer(minLength: 0)
        }
        .background(Brand.inkCard.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isCapturing)
    }

    private var header: some View {
        HStack {
            Text("PayPal")
                .font(.system(.title2, design: .serif).weight(.bold).italic())
            Spacer()
            Text("SANDBOX (DEMO)")
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Self.paypalBlue)
    }

    private func approve() async {
        isCapturing = true
        errorMessage = nil
        defer { isCapturing = false }
        do {
            let confirmed = try await bookings.capturePayPal(booking)
            onConfirmed(confirmed)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// PayPal's yellow call-to-action, used on the mock sheet and the "Continue to PayPal" bar.
    struct PayPalButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.headline)
                .foregroundStyle(paypalBlue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(paypalYellow.opacity(configuration.isPressed ? 0.8 : 1),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// In-app Safari for a live PayPal approval page. The caller captures the order once this is dismissed.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(Brand.gold)
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
