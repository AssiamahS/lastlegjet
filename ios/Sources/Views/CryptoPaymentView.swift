import SwiftUI

/// CRYPTO rail: pick an asset → `/pay` locks a rate → show amount, address, countdown → confirm.
/// In mock mode "I've sent it (demo)" calls `/confirm-mock`; live mode polls the booking until the
/// provider webhook flips it to CONFIRMED.
struct CryptoPaymentView: View {
    let booking: Booking
    let info: PaymentMethodInfo
    let onConfirmed: (Booking) -> Void

    @EnvironmentObject private var bookings: BookingsStore

    @State private var asset: CryptoAsset = .btc
    @State private var pay: PayResponse?
    @State private var isBusy = false
    @State private var errorMessage: String?

    private static let pollSeconds = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RailTitle(title: "Pay with crypto", info: info)
            Text("Pay ")
                + Text(booking.totalText).foregroundStyle(Brand.cream).bold()
                + Text(" in the asset of your choice. The exchange rate is locked for 15 minutes once you generate payment details.")

            assetChips

            if let charge = pay?.crypto {
                chargeDetails(charge, mock: pay?.isMock ?? true)
            } else {
                Button {
                    Task { await createCharge() }
                } label: {
                    if isBusy {
                        ProgressView().tint(Brand.ink)
                    } else {
                        Text("Generate \(asset.rawValue) payment details")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isBusy)
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Brand.danger)
            }
        }
        .font(.subheadline)
        .foregroundStyle(Brand.muted)
        .card()
    }

    // MARK: Pieces

    private var assetChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CryptoAsset.allCases) { option in
                    Chip(label: "\(option.rawValue) · \(option.name)", isSelected: asset == option) {
                        asset = option
                    }
                    .disabled(pay != nil)
                    .opacity(pay != nil && asset != option ? 0.5 : 1)
                }
            }
        }
    }

    private func chargeDetails(_ charge: CryptoCharge, mock: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                caption("SEND EXACTLY")
                Text("\(charge.amountText) \(charge.asset.rawValue)")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .foregroundStyle(Brand.gold)
                    .textSelection(.enabled)
                Text("on \(charge.asset.network) · rate locked at \(charge.rateLocked)")
                    .font(.caption)
            }

            VStack(alignment: .leading, spacing: 6) {
                caption("TO ADDRESS")
                CopyableValue(value: charge.address, copyLabel: "Copy address")
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let expired = charge.expiresAt <= context.date
                HStack(spacing: 8) {
                    Image(systemName: expired ? "clock.badge.xmark" : "clock")
                    if expired {
                        Text("Rate lock expired.")
                        Button("Generate new details") { reset() }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.gold)
                    } else {
                        Text("Rate lock expires in ")
                            + Text(DateText.countdown(to: charge.expiresAt, from: context.date)).bold()
                    }
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(expired ? Brand.danger : Brand.gold)
                .padding(10)
                .background((expired ? Brand.danger : Brand.gold).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .task(id: expired) {
                    guard !mock, !expired else { return }
                    await pollUntilConfirmed()
                }
            }

            if let hosted = charge.hostedUrl, let url = URL(string: hosted) {
                Link(destination: url) {
                    Label("Open hosted checkout", systemImage: "arrow.up.right.square")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.gold)
                }
            }

            if mock {
                Button {
                    Task { await confirmMock() }
                } label: {
                    if isBusy {
                        ProgressView().tint(Brand.ink)
                    } else {
                        Text("I've sent it (demo)")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isBusy || charge.expiresAt <= Date())
            } else {
                Text("Waiting for the network… this screen updates automatically once the payment is detected.")
                    .font(.caption)
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .tracking(1)
            .foregroundStyle(Brand.muted)
    }

    // MARK: Actions

    private func createCharge() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let response = try await bookings.startPayment(booking, rail: .crypto, crypto: asset)
            guard response.crypto != nil else {
                errorMessage = "The server did not return crypto payment details."
                return
            }
            pay = response
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirmMock() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            onConfirmed(try await bookings.confirmMock(booking))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func pollUntilConfirmed() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.pollSeconds))
            if Task.isCancelled { return }
            if let latest = try? await bookings.refresh(booking), latest.isConfirmed {
                onConfirmed(latest)
                return
            }
        }
    }

    private func reset() {
        pay = nil
        errorMessage = nil
    }
}
