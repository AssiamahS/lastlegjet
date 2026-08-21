import Foundation

struct User: Codable, Hashable {
    let id: String
    let email: String
    let firstName: String
    let lastName: String
    let role: String

    var fullName: String {
        let name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? email : name
    }

    var roleLabel: String {
        role.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var isCustomer: Bool { role == "CUSTOMER" }
}

struct AuthResponse: Decodable {
    let accessToken: String
    let user: User
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

struct RegisterRequest: Encodable {
    let email: String
    let password: String
    let firstName: String
    let lastName: String
}

/// `GET /v1/meta` → `{ version, paymentMode: "stripe"|"mock", aviationProvider, sampleData }`.
struct ServerMeta: Decodable, Equatable {
    let version: String
    let paymentMode: String
    let aviationProvider: String
    let sampleData: Bool
}
