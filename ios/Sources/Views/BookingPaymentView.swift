import SwiftUI

struct BookingPaymentView: View {
    let booking: Booking

    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var bookings: BookingsStore
    @EnvironmentObject private var mode: AppMode

    @State private var method: PaymentMethod = .card
    @State private var cardNumber = ""
    @State private var expiry = ""
    @State private var cvc = ""
    @State private var cardName = ""
    @State private var isPaying = false
    @State private var errorMessage: String?

    private var isConfirmed: Bool { booking.isConfirmed }
    private var isExpired: Bool { booking.isHeld && booking.holdExpiresAt < Date() || booking.status == BookingStatus.expired.rawValue }

    private var cardFormComplete: Bool {
        !cardNumber.trimmingCharacters(in: .whitespaces).isEmpty
            && !expiry.trimmingCharacters(in: .whitespaces).isEmpty
            && !cvc.trimmingCharacters(in: .whitespaces).isEmpty
            && !cardName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canPay: Bool {
        method.isAvailable && cardFormComplete && booking.isHeld && !isExpired && !isPaying
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StepIndicator(current: isConfirmed ? 3 : 2)
                holdBanner
                flightSummary
                paymentMethod
                if method.isAvailable { cardForm } else { comingSoon }
                orderSummary
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Brand.danger)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .screenBackground()
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { payBar }
        .navigationTitle("Payment")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Sections

    @ViewBuilder
    private var holdBanner: some View {
        if booking.isHeld {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = booking.holdExpiresAt.timeIntervalSince(context.date)
                HStack(spacing: 10) {
                    Image(systemName: remaining > 0 ? "clock.badge.exclamationmark" : "clock.badge.xmark")
                    if remaining > 0 {
                        Text("Seats held for ")
                            + Text(DateText.countdown(to: booking.holdExpiresAt, from: context.date)).bold()
                    } else {
                        Text("Hold expired — please book again")
                    }
                    Spacer()
                    Text(booking.reference)
                        .font(.caption.monospaced())
                }
                .font(.subheadline)
                .foregroundStyle(remaining > 0 ? Brand.gold : Brand.danger)
                .padding(12)
                .background((remaining > 0 ? Brand.gold : Brand.danger).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var flightSummary: some View {
        if let flight = booking.flight {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(flight.routeTitle)
                        .font(.displayHeadline)
                        .foregroundStyle(Brand.cream)
                    Spacer()
                    StatusBadge(status: booking.status)
                }
                Text("\(flight.aircraft.model) · \(flight.departsText)")
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
                Text("\(booking.passengers) passenger\(booking.passengers == 1 ? "" : "s") · \(flight.operatorInfo.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
            }
            .card()
        }
    }

    private var paymentMethod: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Payment method")
            Picker("Payment method", selection: $method) {
                ForEach(PaymentMethod.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var cardForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            BrandField(title: "Card number", text: $cardNumber, keyboard: .numberPad)
            HStack(spacing: 12) {
                BrandField(title: "MM / YY", text: $expiry, keyboard: .numbersAndPunctuation)
                BrandField(title: "CVC", text: $cvc, secure: true)
            }
            BrandField(title: "Name on card", text: $cardName, capitalization: .words)
            Label(mode.isSample || mode.serverMeta?.paymentMode == "mock"
                  ? "Test mode — no card is charged."
                  : "Payments are processed securely.",
                  systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(Brand.muted)
        }
        .card()
    }

    private var comingSoon: some View {
        VStack(spacing: 8) {
            Image(systemName: "hourglass")
                .font(.title2)
                .foregroundStyle(Brand.gold)
            Text("\(method.rawValue) — Coming soon")
                .font(.headline)
                .foregroundStyle(Brand.cream)
            Text("Card is the only payment method available right now.")
                .font(.caption)
                .foregroundStyle(Brand.muted)
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private var orderSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Order summary")
            VStack(spacing: 10) {
                LabeledRow(label: "Base fare", value: booking.baseFareText)
                LabeledRow(label: "Service fee", value: booking.serviceFeeText)
                LabeledRow(label: "Taxes", value: booking.taxText)
                Divider().overlay(Brand.inkLine)
                LabeledRow(label: "Total", value: booking.totalText, emphasize: true)
            }
            .card()
        }
    }

    private var payBar: some View {
        VStack(spacing: 8) {
            if isConfirmed {
                Button("View Confirmation") {
                    nav.push(BookingConfirmationRoute(booking: booking))
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button {
                    Task { await pay() }
                } label: {
                    if isPaying {
                        ProgressView().tint(Brand.ink)
                    } else {
                        Text("Confirm & Pay \(booking.totalText)")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canPay)
            }
        }
        .padding(16)
        .background(Brand.inkCard)
        .overlay(alignment: .top) { Rectangle().fill(Brand.inkLine).frame(height: 1) }
    }

    // MARK: Actions

    private func pay() async {
        isPaying = true
        errorMessage = nil
        defer { isPaying = false }
        do {
            let confirmed = try await bookings.payAndConfirm(booking)
            nav.push(BookingConfirmationRoute(booking: confirmed))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct StepIndicator: View {
    let current: Int
    private let steps = ["Flight Selected", "Payment", "Confirmation"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                let number = index + 1
                let done = number < current
                let active = number == current
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(done || active ? Brand.gold : Brand.inkCard)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().strokeBorder(done || active ? Brand.gold : Brand.inkLine))
                        if done {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(Brand.ink)
                        } else {
                            Text("\(number)")
                                .font(.caption.bold())
                                .foregroundStyle(active ? Brand.ink : Brand.muted)
                        }
                    }
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(active ? Brand.cream : Brand.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                if index < steps.count - 1 {
                    Rectangle()
                        .fill(done ? Brand.gold : Brand.inkLine)
                        .frame(height: 1)
                        .frame(maxWidth: 40)
                        .offset(y: -10)
                }
            }
        }
        .padding(.top, 8)
    }
}
