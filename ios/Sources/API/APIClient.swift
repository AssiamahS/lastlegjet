import Foundation
import Security

enum APIError: LocalizedError {
    case transport(URLError)
    case server(statusCode: Int, message: String)
    case decoding(Error)
    case invalidURL
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .transport(let e):
            return e.localizedDescription
        case .server(_, let message):
            return message
        case .decoding:
            return "The server sent something we couldn't read."
        case .invalidURL:
            return "The API base URL is not valid."
        case .unauthorized:
            return "Please sign in to continue."
        }
    }

    /// True for network-level failures (host unreachable, timeout, no connection).
    var isUnreachable: Bool {
        if case .transport = self { return true }
        if case .invalidURL = self { return true }
        return false
    }
}

/// Nest's default error body: `{ statusCode, message, error }` — `message` may be a string or an array.
struct NestErrorBody: Decodable {
    let statusCode: Int
    let message: String
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case statusCode, message, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        statusCode = try c.decodeIfPresent(Int.self, forKey: .statusCode) ?? 0
        error = try c.decodeIfPresent(String.self, forKey: .error)
        if let single = try? c.decode(String.self, forKey: .message) {
            message = single
        } else if let many = try? c.decode([String].self, forKey: .message) {
            message = many.joined(separator: "\n")
        } else {
            message = error ?? "Request failed"
        }
    }
}

enum APIConfig {
    static let baseURLKey = "apiBaseURL"
    static let useSampleDataKey = "useSampleData"
    /// Public HTTPS API (no ATS exception needed).
    static let defaultBaseURL = "https://lastlegjet-api.sylvesterassiamahpm.workers.dev/v1"
    /// Alternative when developing against the Mac over Tailscale (covered by the ATS exception for tail40af16.ts.net).
    static let tailscaleBaseURL = "http://saints-macbook-air.tail40af16.ts.net:4000/v1"

    static var baseURLString: String {
        let stored = UserDefaults.standard.string(forKey: baseURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? defaultBaseURL : stored
    }
}

private struct AnyEncodable: Encodable {
    let value: Encodable

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}

struct APIClient {
    static let shared = APIClient()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: JSON coding

    static let decoder: JSONDecoder = {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = fractional.date(from: raw) ?? plain.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date: \(raw)")
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractional.string(from: date))
        }
        return e
    }()

    // MARK: Requests

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], auth: Bool = false) async throws -> T {
        try await send(method: "GET", path: path, query: query, body: nil, auth: auth)
    }

    func post<T: Decodable>(_ path: String, body: Encodable? = nil, auth: Bool = true) async throws -> T {
        try await send(method: "POST", path: path, query: [], body: body, auth: auth)
    }

    private func send<T: Decodable>(method: String, path: String, query: [URLQueryItem],
                                    body: Encodable?, auth: Bool) async throws -> T {
        guard var components = URLComponents(string: APIConfig.baseURLString) else {
            throw APIError.invalidURL
        }
        let base = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = base + (path.hasPrefix("/") ? path : "/" + path)
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(AnyEncodable(value: body))
        }
        if auth, let token = Keychain.get(Keychain.tokenKey) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw APIError.transport(urlError)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401 { throw APIError.unauthorized }
            let message = (try? Self.decoder.decode(NestErrorBody.self, from: data))?.message
                ?? "Request failed (\(status))"
            throw APIError.server(statusCode: status, message: message)
        }

        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}

/// Minimal generic-password Keychain wrapper for the bearer token.
enum Keychain {
    static let tokenKey = "accessToken"
    private static let service = "com.assiamah.lastleg"

    private static func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    static func set(_ value: String, for key: String) {
        delete(key)
        guard let data = value.data(using: .utf8) else { return }
        var query = baseQuery(key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }
}
