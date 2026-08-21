import Foundation
import Combine

/// Decides whether the app talks to the API or runs on bundled sample data.
/// `forced` is the Account toggle; `offline` is set automatically when the API is unreachable.
@MainActor
final class AppMode: ObservableObject {
    static let shared = AppMode()

    @Published var forced: Bool {
        didSet { UserDefaults.standard.set(forced, forKey: APIConfig.useSampleDataKey) }
    }
    @Published var offline: Bool = false
    /// Last `/meta` response from the server (nil until fetched or when unreachable).
    @Published var serverMeta: ServerMeta?

    /// Bundled JSON is in use (toggle on, or API unreachable).
    var isSample: Bool { forced || offline }

    /// Show the "Sample data" banner: bundled data, or the server itself reports seeded sample data.
    var showsSampleBanner: Bool { isSample || (serverMeta?.sampleData ?? false) }

    var bannerText: String {
        if forced { return "Sample data — bundled, sample mode on" }
        if offline { return "Sample data — server unreachable" }
        return "Sample data — server is running seed data"
    }

    private init() {
        forced = UserDefaults.standard.bool(forKey: APIConfig.useSampleDataKey)
    }

    /// Fetches `/meta` on launch (and when the base URL changes). Marks offline on transport failure.
    func refreshMeta() async {
        guard !forced else { return }
        do {
            let meta: ServerMeta = try await APIClient.shared.get("/meta")
            serverMeta = meta
            offline = false
        } catch let error as APIError where error.isUnreachable {
            serverMeta = nil
            offline = true
        } catch {
            serverMeta = nil
        }
    }
}
