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
            return "Connected · API v\(meta.version) · payments \(meta.paymentMode)\(meta.sampleData ? " · seed data" : "")"
        }
        return "Connected"
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

    private var canSubmit: Bool {
        let base = !email.trimmingCharacters(in: .whitespaces).isEmpty && password.count >= 8
        if isRegistering {
            return base && !firstName.trimmingCharacters(in: .whitespaces).isEmpty
                && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return base
    }

    var body: some View {
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
        let ok: Bool
        if isRegistering {
            ok = await session.signUp(email: email, password: password, firstName: firstName, lastName: lastName)
        } else {
            ok = await session.signIn(email: email, password: password)
        }
        if ok { onSuccess() }
    }
}
