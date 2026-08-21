import Foundation

struct Airport: Codable, Hashable, Identifiable {
    let id: String
    let iata: String
    let icao: String?
    let name: String
    let city: String
    let country: String
    let lat: Double
    let lng: Double
    let timezone: String

    var label: String { "\(city) (\(iata))" }

    /// Case-insensitive match on IATA, city or name, used for offline autocomplete.
    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return false }
        return iata.lowercased().hasPrefix(q)
            || city.lowercased().contains(q)
            || name.lowercased().contains(q)
    }
}
