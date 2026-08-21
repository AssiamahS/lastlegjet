import Foundation

/// Loads the JSON captured from the live API (`Resources/SampleData`) for offline / demo mode.
enum SampleData {
    static func flights() -> [Flight] {
        guard let page: FlightPage = load("flights") else { return [] }
        return page.items
    }

    static func flightDetail(id: String) -> FlightDetail? {
        if let detail: FlightDetail = load("flight-detail-\(id)") {
            return detail
        }
        guard let flight = flights().first(where: { $0.id == id }) else { return nil }
        return FlightDetail(flight: flight, similar: [])
    }

    static func airports() -> [Airport] {
        load("airports") ?? []
    }

    static func airports(matching query: String) -> [Airport] {
        let all = airports()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return Array(all.filter { $0.matches(q) }.prefix(20))
    }

    /// Demo customer used when booking locally without a server.
    static let guestUser = User(id: "sample_user", email: "guest@lastlegjet.dev",
                                firstName: "Guest", lastName: "Traveller", role: "CUSTOMER")

    private static func load<T: Decodable>(_ name: String) -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? APIClient.decoder.decode(T.self, from: data)
    }
}
