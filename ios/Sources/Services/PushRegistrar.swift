import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// Push registration stub: asks for notification permission, registers with APNs, and posts the
/// token to `POST /v1/devices`. The app carries no `aps-environment` entitlement yet (that would
/// change cloud signing), so APNs registration normally fails and only local notifications show;
/// the upload path is ready for when the entitlement is added.
@MainActor
final class PushRegistrar: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushRegistrar()

    private static let tokenKey = "push.deviceToken"
    private static let uploadedKey = "push.uploadedToken"

    private(set) var deviceToken: String? = UserDefaults.standard.string(forKey: tokenKey)
    private(set) var lastError: String?
    private(set) var permissionGranted = false

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Called once the user is signed in: permission prompt, APNs registration, token upload.
    func requestAndRegister() async {
        let center = UNUserNotificationCenter.current()
        do {
            permissionGranted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            lastError = error.localizedDescription
        }
        #if canImport(UIKit)
        UIApplication.shared.registerForRemoteNotifications()
        #endif
        await uploadIfNeeded()
    }

    func didRegister(tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        UserDefaults.standard.set(token, forKey: Self.tokenKey)
        Task { await uploadIfNeeded() }
    }

    func didFail(_ error: Error) {
        lastError = error.localizedDescription
    }

    /// `POST /v1/devices { platform: "ios", token }` once per token; quiet when the route isn't deployed.
    func uploadIfNeeded() async {
        guard let token = deviceToken, !AppMode.shared.isSample, Keychain.get(Keychain.tokenKey) != nil else { return }
        guard UserDefaults.standard.string(forKey: Self.uploadedKey) != token else { return }
        do {
            let _: OkResponse = try await APIClient.shared.post("/devices",
                                                                body: DeviceRegistrationBody(platform: "ios", token: token),
                                                                auth: true)
            UserDefaults.standard.set(token, forKey: Self.uploadedKey)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Forget the uploaded marker so the next account re-registers the token.
    func signedOut() {
        UserDefaults.standard.removeObject(forKey: Self.uploadedKey)
    }

    func notifyLocally(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
