import SwiftUI

/// Two-factor enrolment: `POST /auth/mfa/setup` → QR + secret → authenticator code → `POST /auth/mfa/enable`.
struct MfaSetupSheet: View {
    let onEnabled: () -> Void

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var setup: MfaSetupResponse?
    @State private var code = ""
    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Set up two-factor")
                        .font(.displayTitle)
                        .foregroundStyle(Brand.cream)
                    Text("Scan the QR code with an authenticator app (1Password, Google Authenticator, Authy…), then enter the 6-digit code it shows.")
                        .font(.subheadline)
                        .foregroundStyle(Brand.muted)

                    if let setup = setup {
                        qrCard(setup)
                        MfaCodeForm(code: $code, errorMessage: errorMessage, isBusy: isBusy,
                                    submitTitle: "Turn on two-factor") { await enable() }
                    } else if let errorMessage = errorMessage {
                        EmptyState(icon: "exclamationmark.triangle", title: "Couldn't start setup", message: errorMessage)
                        Button("Try again") { Task { await load() } }
                            .buttonStyle(SecondaryButtonStyle())
                    } else {
                        ProgressView().tint(Brand.gold).frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isBusy)
                }
            }
        }
        .presentationDetents([.large])
        .task { await load() }
    }

    private func qrCard(_ setup: MfaSetupResponse) -> some View {
        VStack(spacing: 14) {
            if let data = setup.qrImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(8)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text("QR image unavailable — add the key manually.")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("CAN'T SCAN? ENTER THIS KEY")
                    .font(.caption2.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(Brand.muted)
                CopyableValue(value: setup.secret, copyLabel: "Copy key")
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private func load() async {
        errorMessage = nil
        do {
            setup = try await session.setUpMfa()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func enable() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await session.enableMfa(code: code)
            onEnabled()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Turning two-factor off requires a current authenticator code (`POST /auth/mfa/disable`).
struct MfaDisableSheet: View {
    let onDisabled: () -> Void

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Turn off two-factor")
                    .font(.displayTitle)
                    .foregroundStyle(Brand.cream)
                Text("Enter the current 6-digit code from your authenticator app to confirm.")
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
                MfaCodeForm(code: $code, errorMessage: errorMessage, isBusy: isBusy,
                            submitTitle: "Turn off two-factor") { await disable() }
                Spacer()
            }
            .padding(16)
            .screenBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isBusy)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func disable() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await session.disableMfa(code: code)
            onDisabled()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Code field + error line + submit button, shared by sign-in, enrolment and disable.
struct MfaCodeForm: View {
    @Binding var code: String
    let errorMessage: String?
    let isBusy: Bool
    let submitTitle: String
    let submit: () async -> Void

    var body: some View {
        MfaCodeField(code: $code)
        if let errorMessage = errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(Brand.danger)
        }
        Button {
            Task { await submit() }
        } label: {
            if isBusy {
                ProgressView().tint(Brand.ink)
            } else {
                Text(submitTitle)
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!MfaCodeField.isComplete(code) || isBusy)
    }
}

/// Six-digit authenticator code entry.
struct MfaCodeField: View {
    @Binding var code: String

    static let length = 6

    static func isComplete(_ code: String) -> Bool {
        code.count == length && code.allSatisfy(\.isNumber)
    }

    var body: some View {
        BrandField(title: "6-digit code", text: $code, keyboard: .numberPad)
            .font(.title3.monospaced())
            .textContentType(.oneTimeCode)
            .onChange(of: code) { _, newValue in
                let digits = newValue.filter(\.isNumber)
                if digits.count > Self.length || digits != newValue {
                    code = String(digits.prefix(Self.length))
                }
            }
    }
}
