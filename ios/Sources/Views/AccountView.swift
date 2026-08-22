import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var mode: AppMode
    @EnvironmentObject private var flights: FlightsStore
    @AppStorage(APIConfig.baseURLKey) private var apiBaseURL: String = APIConfig.defaultBaseURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Account")
                        .font(.displayLarge)
                        .foregroundStyle(Brand.cream)
                        .padding(.top, 8)
                    if let user = session.user {
                        signedInCard(user)
                        SecuritySection(user: user)
                    } else {
                        AuthFormView(onSuccess: {})
                    }
                    serverSection
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func signedInCard(_ user: User) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Brand.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.fullName)
                        .font(.headline)
                        .foregroundStyle(Brand.cream)
                    Text(user.email)
                        .font(.subheadline)
                        .foregroundStyle(Brand.muted)
                }
                Spacer()
                Pill(text: user.roleLabel, systemImage: "person.text.rectangle")
            }
            if !user.isCustomer {
                Text("Bookings require a customer account. Operator and admin accounts can browse only.")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
            }
            Button("Sign Out") { session.signOut() }
                .buttonStyle(SecondaryButtonStyle())
        }
        .card()
    }

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Server")
            VStack(alignment: .leading, spacing: 12) {
                Text("API base URL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.muted)
                BrandField(title: APIConfig.defaultBaseURL, text: $apiBaseURL, keyboard: .URL)
                    .font(.footnote.monospaced())
                HStack(spacing: 12) {
                    Button("Public API") { apiBaseURL = APIConfig.defaultBaseURL }
                    Button("Tailscale Mac") { apiBaseURL = APIConfig.tailscaleBaseURL }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Brand.gold)

                Toggle(isOn: $mode.forced) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use sample data")
                            .foregroundStyle(Brand.cream)
                        Text("Bundled flights, bookings stay on this device")
                            .font(.caption)
                            .foregroundStyle(Brand.muted)
                    }
                }
                .tint(Brand.gold)

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                    Spacer()
                    Button("Check") {
                        Task {
                            await mode.refreshMeta()
                            await flights.search()
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.gold)
                }
            }
            .card()
        }
        .onChange(of: apiBaseURL) { _, _ in
            Task { await mode.refreshMeta() }
        }
    }

    private var statusColor: Color {
        if mode.forced { return Brand.gold }
        return mode.offline ? Brand.danger : Brand.success
    }

    private var statusText: String {
        if mode.forced { return "Sample mode — not contacting the server" }
        if mode.offline { return "Server unreachable — showing sample data" }
        if let meta = mode.serverMeta {
            return "Connected · API v\(meta.version) · payments \(meta.paymentMode)\(railsSummary(meta.rails))\(meta.sampleData ? " · seed data" : "")"
        }
        return "Connected"
    }

    /// " · 4 rails (mock)" / " · 4 rails (2 live)" from `/meta.rails`; empty for servers that predate it.
    private func railsSummary(_ rails: PaymentRails?) -> String {
        guard let rails = rails else { return "" }
        let modes = [rails.card, rails.paypal, rails.klarna, rails.crypto]
        let live = modes.filter { $0 != "mock" }.count
        return " · \(modes.count) rails (\(live == 0 ? "mock" : "\(live) live"))"
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text(Brand.appName)
                .font(.system(.footnote, design: .serif).weight(.semibold))
                .foregroundStyle(Brand.gold)
            Text("Empty-leg private jet marketplace · v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                .font(.caption2)
                .foregroundStyle(Brand.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }
}

/// Sign in / create account form shared by the Account tab and the booking sign-in sheet.
struct AuthFormView: View {
    let onSuccess: () -> Void

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var mode: AppMode

    @State private var isRegistering = false
    @State private var email = ""
    @State private var password = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var mfaCode = ""

    private var canSubmit: Bool {
        let base = !email.trimmingCharacters(in: .whitespaces).isEmpty && password.count >= 8
        if isRegistering {
            return base && !firstName.trimmingCharacters(in: .whitespaces).isEmpty
                && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return base
    }

    var body: some View {
        if session.pendingMfaToken != nil {
            mfaStep
        } else {
            credentialsForm
        }
    }

    /// Second factor after `/auth/login` answered `mfaRequired`.
    private var mfaStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Two-factor authentication", systemImage: "lock.shield")
                .font(.headline)
                .foregroundStyle(Brand.cream)
            Text("Enter the 6-digit code from your authenticator app to finish signing in.")
                .font(.subheadline)
                .foregroundStyle(Brand.muted)
            MfaCodeForm(code: $mfaCode, errorMessage: session.errorMessage, isBusy: session.isBusy,
                        submitTitle: "Verify") {
                if await session.verifyMfa(code: mfaCode) { onSuccess() }
            }
            Button("Back to sign in") {
                mfaCode = ""
                session.cancelMfa()
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(session.isBusy)
        }
        .card()
    }

    private var credentialsForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Mode", selection: $isRegistering) {
                Text("Sign In").tag(false)
                Text("Create Account").tag(true)
            }
            .pickerStyle(.segmented)

            if isRegistering {
                HStack(spacing: 12) {
                    BrandField(title: "First name", text: $firstName, capitalization: .words)
                    BrandField(title: "Last name", text: $lastName, capitalization: .words)
                }
            }
            BrandField(title: "Email", text: $email, keyboard: .emailAddress)
            BrandField(title: "Password (8+ characters)", text: $password, secure: true)

            if let error = session.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Brand.danger)
            }
            if mode.forced {
                Text("Sample mode is on — bookings work without an account.")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
            }

            Button {
                Task { await submit() }
            } label: {
                if session.isBusy {
                    ProgressView().tint(Brand.ink)
                } else {
                    Text(isRegistering ? "Create Account" : "Sign In")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSubmit || session.isBusy)
        }
        .card()
    }

    private func submit() async {
        if isRegistering {
            if await session.signUp(email: email, password: password, firstName: firstName, lastName: lastName) {
                onSuccess()
            }
            return
        }
        // `.mfaRequired` swaps this form for the code step; `.failed` shows `session.errorMessage`.
        if await session.signIn(email: email, password: password) == .signedIn {
            onSuccess()
        }
    }
}

/// Email verification + two-factor status from `/me`, with the actions to change them.
struct SecuritySection: View {
    let user: User

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var mode: AppMode

    @State private var showMfaSetup = false
    @State private var showMfaDisable = false
    @State private var showTokenEntry = false
    @State private var verificationToken = ""
    @State private var isBusy = false
    @State private var notice: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Security")
            VStack(alignment: .leading, spacing: 14) {
                emailRow
                Divider().overlay(Brand.inkLine)
                mfaRow
                if let notice = notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(Brand.success)
                }
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Brand.danger)
                }
                if mode.isSample {
                    Text("Security settings need the server — switch off sample data to change them.")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                }
            }
            .card()
        }
        .disabled(mode.isSample)
        .sheet(isPresented: $showMfaSetup) {
            MfaSetupSheet { notice = "Two-factor is on. You'll be asked for a code at every sign-in." }
        }
        .sheet(isPresented: $showMfaDisable) {
            MfaDisableSheet { notice = "Two-factor is off." }
        }
        .task(id: user.id) { await session.refreshMe() }
    }

    private var emailRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Email")
                        .font(.subheadline)
                        .foregroundStyle(Brand.cream)
                    Text(user.email)
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                }
                Spacer()
                if let verifiedAt = user.emailVerifiedAt {
                    Pill(text: "Verified \(DateText.short(verifiedAt))", systemImage: "checkmark.seal.fill", tint: Brand.success)
                } else {
                    Pill(text: "Not verified", systemImage: "exclamationmark.circle", tint: Brand.danger)
                }
            }
            if !user.isEmailVerified {
                HStack(spacing: 16) {
                    Button("Resend verification") { Task { await resend() } }
                    Button(showTokenEntry ? "Hide token entry" : "Enter token") { showTokenEntry.toggle() }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Brand.gold)
                .disabled(isBusy)
                if showTokenEntry {
                    HStack(spacing: 8) {
                        BrandField(title: "Token from the email", text: $verificationToken)
                            .font(.footnote.monospaced())
                        Button("Verify") { Task { await verify() } }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.gold)
                            .disabled(verificationToken.trimmingCharacters(in: .whitespaces).count < 16 || isBusy)
                    }
                }
            }
        }
    }

    private var mfaRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Two-factor authentication")
                    .font(.subheadline)
                    .foregroundStyle(Brand.cream)
                Text(user.isMfaEnabled
                     ? "Authenticator code required at sign-in"
                     : "Add an authenticator app for a second sign-in step")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
            }
            Spacer()
            if user.isMfaEnabled {
                Button("Turn off") { showMfaDisable = true }
                    .buttonStyle(.bordered)
                    .tint(Brand.danger)
            } else {
                Button("Set up") { showMfaSetup = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.gold)
                    .foregroundStyle(Brand.ink)
            }
        }
        .font(.caption.weight(.semibold))
    }

    private func resend() async {
        isBusy = true
        notice = nil
        errorMessage = nil
        defer { isBusy = false }
        do {
            let sent = try await session.resendVerification()
            notice = "Verification email sent — the link is valid until \(DateText.short(sent.expiresAt))."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verify() async {
        isBusy = true
        notice = nil
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await session.verifyEmail(token: verificationToken)
            verificationToken = ""
            showTokenEntry = false
            notice = "Email verified."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
