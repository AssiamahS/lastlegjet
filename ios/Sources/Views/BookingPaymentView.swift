import SwiftUI

struct BookingPaymentView: View {
    let booking: Booking

    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var bookings: BookingsStore
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var mode: AppMode

    @State private var methods: [PaymentMethodInfo] = []
    @State private var rail: PaymentRail = .card
    @State private var cardNumber = ""
    @State private var expiry = ""
    @State private var cvc = ""
    @State private var cardName = ""
    @State private var isPaying = false
    @State private var errorMessage: String?
    @State private var showPayPalMock = false
    @State private var paypalApproval: PayPalApproval?

    private var isConfirmed: Bool { booking.isConfirmed }
    private var isExpired: Bool { booking.isHeld && booking.holdExpiresAt < Date() || booking.status == BookingStatus.expired.rawValue }
    private var selected: PaymentMethodInfo? { methods.first { $0.method == rail } }
    private var payable: Bool { booking.isHeld && !isExpired && !isPaying }

    private var cardFormComplete: Bool {
        !cardNumber.trimmingCharacters(in: .whitespaces).isEmpty
            && !expiry.trimmingCharacters(in: .whitespaces).isEmpty
            && !cvc.trimmingCharacters(in: .whitespaces).isEmpty
            && !cardName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StepIndicator(current: isConfirmed ? 3 : 2)
                holdBanner
                flightSummary
                paymentMethods
                railPanel
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
        .task(id: mode.isSample) { await loadMethods() }
        .sheet(isPresented: $showPayPalMock) {
            PayPalMockSheet(booking: booking, payerEmail: session.user?.email ?? SampleData.guestUser.email) { confirmed in
                showPayPalMock = false
                finish(confirmed)
            }
        }
        .sheet(item: $paypalApproval, onDismiss: { Task { await capturePayPal() } }) { approval in
            SafariView(url: approval.url).ignoresSafeArea()
        }
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

    /// Tabs come from `GET /payments/methods`; disabled rails stay visible with the server's note.
    private var paymentMethods: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Payment method")
            if methods.isEmpty {
                ProgressView().tint(Brand.gold).frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 8) {
                    ForEach(methods) { info in
                        PaymentRailTile(info: info, isSelected: info.method == rail) {
                            rail = info.method
                            errorMessage = nil
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var railPanel: some View {
        if let info = selected {
            if !info.enabled {
                unavailable(info)
            } else {
                switch info.method {
                case .card:
                    cardForm(info, title: "Pay with card")
                case .klarna:
                    cardForm(info, title: "Pay in 4 with Klarna")
                case .paypal:
                    paypalPanel(info)
                case .crypto:
                    CryptoPaymentView(booking: booking, info: info) { confirmed in finish(confirmed) }
                }
            }
        }
    }

    private func cardForm(_ info: PaymentMethodInfo, title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RailTitle(title: title, info: info)
            if info.method == .klarna { klarnaSchedule }
            BrandField(title: "Card number", text: $cardNumber, keyboard: .numberPad)
            HStack(spacing: 12) {
                BrandField(title: "MM / YY", text: $expiry, keyboard: .numbersAndPunctuation)
                BrandField(title: "CVC", text: $cvc, secure: true)
            }
            BrandField(title: "Name on card", text: $cardName, capitalization: .words)
            Label(info.isMock ? (info.note ?? "Test mode — no card is charged.") : "Payments are processed securely.",
                  systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(Brand.muted)
        }
        .card()
    }

    /// Klarna "Pay in 4": total split into four equal instalments, two weeks apart.
    private var klarnaSchedule: some View {
        let instalment = Money.format(cents: Int((Double(booking.totalCents) / 4).rounded()), currency: booking.currency)
        let labels = ["Today", "In 2 weeks", "In 4 weeks", "In 6 weeks"]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { index in
                    VStack(spacing: 4) {
                        Capsule()
                            .fill(index == 0 ? Brand.gold : Brand.inkLine)
                            .frame(height: 4)
                        Text(instalment)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.cream)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(labels[index])
                            .font(.caption2)
                            .foregroundStyle(Brand.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("4 interest-free payments of \(instalment). In test mode the same card form stands in for the Klarna checkout.")
                .font(.caption)
                .foregroundStyle(Brand.muted)
        }
        .padding(12)
        .background(Brand.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func paypalPanel(_ info: PaymentMethodInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            RailTitle(title: "Pay with PayPal", info: info)
            Text("You'll be taken to PayPal to approve a payment of ")
                + Text(booking.totalText).foregroundStyle(Brand.cream).bold()
                + Text(". Your seats stay held while you approve; come back here and the booking confirms automatically.")
            if let note = info.note {
                Text(note)
                    .font(.caption)
            }
        }
        .font(.subheadline)
        .foregroundStyle(Brand.muted)
        .card()
    }

    private func unavailable(_ info: PaymentMethodInfo) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "hourglass")
                .font(.title2)
                .foregroundStyle(Brand.gold)
            Text("\(info.title) — not available yet")
                .font(.headline)
                .foregroundStyle(Brand.cream)
            Text(info.note ?? "This payment method is not available yet.")
                .font(.caption)
                .foregroundStyle(Brand.muted)
                .multilineTextAlignment(.center)
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

    /// Bottom action: card/Klarna confirm, PayPal hand-off, or confirmation. Crypto drives its own buttons.
    @ViewBuilder
    private var payBar: some View {
        if isConfirmed {
            bar {
                Button("View Confirmation") { nav.push(BookingConfirmationRoute(booking: booking)) }
                    .buttonStyle(PrimaryButtonStyle())
            }
        } else if let info = selected, info.enabled, info.method != .crypto {
            bar {
                Button {
                    Task { await pay(info) }
                } label: {
                    if isPaying {
                        ProgressView().tint(Brand.ink)
                    } else if info.method == .paypal {
                        Label("Continue to PayPal", systemImage: "arrow.up.right.square")
                    } else {
                        Text("Confirm & Pay \(booking.totalText)")
                    }
                }
                .buttonStyle(info.method == .paypal ? AnyButtonStyle(PayPalMockSheet.PayPalButtonStyle()) : AnyButtonStyle(PrimaryButtonStyle()))
                .disabled(!payable || (info.method != .paypal && !cardFormComplete))
            }
        }
    }

    private func bar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(Brand.inkCard)
            .overlay(alignment: .top) { Rectangle().fill(Brand.inkLine).frame(height: 1) }
    }

    // MARK: Actions

    private func loadMethods() async {
        methods = await bookings.paymentMethods(currency: booking.currency)
        if selected == nil || selected?.enabled == false {
            rail = methods.first { $0.enabled }?.method ?? .card
        }
    }

    private func pay(_ info: PaymentMethodInfo) async {
        isPaying = true
        errorMessage = nil
        defer { isPaying = false }
        do {
            switch info.method {
            case .paypal:
                let pay = try await bookings.startPayment(booking, rail: .paypal)
                if pay.isMock {
                    showPayPalMock = true
                } else if let url = pay.approvalURL {
                    paypalApproval = PayPalApproval(url: url)
                } else {
                    errorMessage = "PayPal did not return an approval link. Please try another payment method."
                }
            case .card, .klarna:
                finish(try await bookings.payAndConfirm(booking, rail: info.method))
            case .crypto:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Live PayPal: the approval page was dismissed, so capture the order and confirm.
    private func capturePayPal() async {
        isPaying = true
        errorMessage = nil
        defer { isPaying = false }
        do {
            finish(try await bookings.capturePayPal(booking))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finish(_ confirmed: Booking) {
        nav.push(BookingConfirmationRoute(booking: confirmed))
    }
}

/// Live PayPal approval page shown in Safari; `Identifiable` so it can drive `.sheet(item:)`.
private struct PayPalApproval: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// One checkout tab: icon, label, "Test" tag for mock rails, dimmed with the server note when disabled.
struct PaymentRailTile: View {
    let info: PaymentMethodInfo
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: info.method.systemImage)
                    .font(.title2)
                    .foregroundStyle(isSelected ? Brand.gold : Brand.cream)
                Text(info.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? Brand.cream : Brand.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !info.enabled {
                    Text("Soon")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Brand.muted)
                } else if info.isMock {
                    Text("TEST")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Brand.gold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .background(isSelected ? Brand.gold.opacity(0.12) : Brand.inkCard,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Brand.gold : Brand.inkLine))
            .opacity(info.enabled ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(info.enabled ? info.title : "\(info.title), \(info.note ?? "not available")")
    }
}

/// Rail panel heading with a "TEST MODE" tag when the server runs that rail in mock mode.
struct RailTitle: View {
    let title: String
    let info: PaymentMethodInfo

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.displayHeadline)
                .foregroundStyle(Brand.cream)
            if info.isMock {
                Text("TEST MODE")
                    .font(.caption2.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(Brand.gold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Brand.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}

/// Type-erased button style so one button can swap between brand and PayPal styling.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
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
