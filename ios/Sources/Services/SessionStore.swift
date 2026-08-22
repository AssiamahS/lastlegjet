import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var user: User?
    @Published var isBusy = false
    @Published var errorMessage: String?
    /// Set when `/auth/login` answered `mfaRequired`; cleared once the code is verified or the attempt is abandoned.
    @Published private(set) var pendingMfaToken: String?

    private static let userKey = "session.user"
    private let api = APIClient.shared

    var isSignedIn: Bool { user != nil }
    var token: String? { Keychain.get(Keychain.tokenKey) }

    /// Restores the cached user and revalidates the token against `/me` when online.
    func restore() async {
        if let data = UserDefaults.standard.data(forKey: Self.userKey),
           let cached = try? APIClient.decoder.decode(User.self, from: data) {
            user = cached
        }
        guard token != nil, !AppMode.shared.forced else { return }
        do {
            let me: User = try await api.get("/me", auth: true)
            store(user: me)
        } catch let error as APIError {
            if case .unauthorized = error { signOut() }
        } catch {
            // offline: keep cached session
        }
    }

    enum SignInOutcome {
        case signedIn
        case mfaRequired
        case failed
    }

    func signIn(email: String, password: String) async -> SignInOutcome {
        isBusy = true
        errorMessage = nil
        pendingMfaToken = nil
        defer { isBusy = false }
        do {
            let body = LoginRequest(email: email.trimmingCharacters(in: .whitespaces), password: password)
            let result: LoginResult = try await api.post("/auth/login", body: body, auth: false)
            switch result {
            case .authenticated(let response):
                complete(response)
                return .signedIn
            case .mfaRequired(let token):
                pendingMfaToken = token
                return .mfaRequired
            }
        } catch {
            errorMessage = describe(error)
            return .failed
        }
    }

    /// Second step of sign-in: exchanges the pending `mfaToken` plus the authenticator code for a session.
    func verifyMfa(code: String) async -> Bool {
        guard let token = pendingMfaToken else { return false }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let body = MfaVerifyRequest(mfaToken: token, code: code.trimmingCharacters(in: .whitespaces))
            let response: AuthResponse = try await api.post("/auth/mfa/verify", body: body, auth: false)
            pendingMfaToken = nil
            complete(response)
            return true
        } catch {
            errorMessage = describe(error)
            return false
        }
    }

    func cancelMfa() {
        pendingMfaToken = nil
        errorMessage = nil
    }

    func signUp(email: String, password: String, firstName: String, lastName: String) async -> Bool {
        await authenticate(path: "/auth/register",
                           body: RegisterRequest(email: email.trimmingCharacters(in: .whitespaces),
                                                 password: password,
                                                 firstName: firstName.trimmingCharacters(in: .whitespaces),
                                                 lastName: lastName.trimmingCharacters(in: .whitespaces)))
    }

    func signOut() {
        Keychain.delete(Keychain.tokenKey)
        UserDefaults.standard.removeObject(forKey: Self.userKey)
        user = nil
        pendingMfaToken = nil
    }

    // MARK: Security (email verification, two-factor)

    /// Re-fetches `/me` so `emailVerifiedAt` / `mfaEnabled` reflect the latest server state.
    func refreshMe() async {
        guard token != nil else { return }
        if let me: User = try? await api.get("/me", auth: true) {
            store(user: me)
        }
    }

    func resendVerification() async throws -> VerificationSent {
        try await api.post("/auth/resend-verification", auth: true)
    }

    func verifyEmail(token: String) async throws {
        let _: EmailVerified = try await api.post("/auth/verify-email",
                                                  body: VerifyEmailRequest(token: token.trimmingCharacters(in: .whitespaces)),
                                                  auth: false)
        await refreshMe()
    }

    func setUpMfa() async throws -> MfaSetupResponse {
        try await api.post("/auth/mfa/setup", auth: true)
    }

    func enableMfa(code: String) async throws {
        let _: MfaStatus = try await api.post("/auth/mfa/enable", body: MfaCodeRequest(code: code), auth: true)
        await refreshMe()
    }

    func disableMfa(code: String) async throws {
        let _: MfaStatus = try await api.post("/auth/mfa/disable", body: MfaCodeRequest(code: code), auth: true)
        await refreshMe()
    }

    // MARK: Helpers

    private func authenticate(path: String, body: Encodable) async -> Bool {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let response: AuthResponse = try await api.post(path, body: body, auth: false)
            complete(response)
            return true
        } catch {
            errorMessage = describe(error)
            return false
        }
    }

    private func complete(_ response: AuthResponse) {
        Keychain.set(response.accessToken, for: Keychain.tokenKey)
        store(user: response.user)
    }

    private func describe(_ error: Error) -> String {
        if let apiError = error as? APIError, apiError.isUnreachable {
            return "Can't reach the server. Check the API base URL in Account, or switch on sample data."
        }
        return error.localizedDescription
    }

    private func store(user: User) {
        self.user = user
        if let data = try? APIClient.encoder.encode(user) {
            UserDefaults.standard.set(data, forKey: Self.userKey)
        }
    }
}
