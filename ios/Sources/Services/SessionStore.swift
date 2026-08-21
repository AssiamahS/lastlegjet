import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var user: User?
    @Published var isBusy = false
    @Published var errorMessage: String?

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

    func signIn(email: String, password: String) async -> Bool {
        await authenticate(path: "/auth/login",
                           body: LoginRequest(email: email.trimmingCharacters(in: .whitespaces), password: password))
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
    }

    private func authenticate(path: String, body: Encodable) async -> Bool {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let response: AuthResponse = try await api.post(path, body: body, auth: false)
            Keychain.set(response.accessToken, for: Keychain.tokenKey)
            store(user: response.user)
            return true
        } catch let error as APIError {
            errorMessage = error.isUnreachable
                ? "Can't reach the server. Check the API base URL in Account, or switch on sample data."
                : error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }

    private func store(user: User) {
        self.user = user
        if let data = try? APIClient.encoder.encode(user) {
            UserDefaults.standard.set(data, forKey: Self.userKey)
        }
    }
}
