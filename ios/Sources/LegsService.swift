import Foundation

struct Leg: Codable, Identifiable, Hashable {
    let id: String
    let date: String
    let sort: String
    let from: String
    let to: String
    let fromCity: String
    let toCity: String
    let aircraft: String
    let category: String
    let seats: Int
    let operatorName: String
    let price: String

    enum CodingKeys: String, CodingKey {
        case id, date, sort, from, to, aircraft, category, seats, price
        case fromCity = "from_city"
        case toCity = "to_city"
        case operatorName = "operator"
    }
}

struct LegsFeed: Codable {
    let updated: String
    let source: String
    let legs: [Leg]
}

@MainActor
final class LegsService: ObservableObject {
    @Published var legs: [Leg] = []
    @Published var updated: String = ""
    @Published var loading = false
    @Published var error: String?

    private static let feedURL = URL(string: "https://lastleg.pages.dev/legs.json")!
    private static let cacheKey = "legs.cache.v1"

    func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            var request = URLRequest(url: Self.feedURL)
            request.cachePolicy = .reloadRevalidatingCacheData
            let (data, _) = try await URLSession.shared.data(for: request)
            apply(data)
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        } catch {
            if let cached = UserDefaults.standard.data(forKey: Self.cacheKey) {
                apply(cached)
            } else {
                self.error = "Couldn't reach the board. Pull to retry."
            }
        }
    }

    private func apply(_ data: Data) {
        guard let feed = try? JSONDecoder().decode(LegsFeed.self, from: data) else {
            error = "Board data unreadable."
            return
        }
        legs = feed.legs.sorted { $0.sort < $1.sort }
        updated = feed.updated
    }
}
