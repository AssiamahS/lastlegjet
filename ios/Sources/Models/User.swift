import Foundation

struct User: Codable, Hashable {
    let id: String
    let email: String
    let firstName: String
    let lastName: String
    let role: String
    /// Present on `/me` and auth responses from API 0.3+; nil when the server is older or the user is cached from 2.0.
    let emailVerifiedAt: Date?
    let mfaEnabled: Bool?

    var isEmailVerified: Bool { emailVerifiedAt != nil }
    var isMfaEnabled: Bool { mfaEnabled ?? false }

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

/// `POST /auth/login` either signs in straight away or, when 2FA is on, hands back a short-lived `mfaToken`.
enum LoginResult: Decodable {
    case authenticated(AuthResponse)
    case mfaRequired(mfaToken: String)

    private enum CodingKeys: String, CodingKey {
        case mfaRequired, mfaToken
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if try container.decodeIfPresent(Bool.self, forKey: .mfaRequired) == true {
            self = .mfaRequired(mfaToken: try container.decode(String.self, forKey: .mfaToken))
        } else {
            self = .authenticated(try AuthResponse(from: decoder))
        }
    }
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

/// `POST /auth/mfa/verify` body.
struct MfaVerifyRequest: Encodable {
    let mfaToken: String
    let code: String
}

/// `POST /auth/mfa/enable` and `/auth/mfa/disable` body.
struct MfaCodeRequest: Encodable {
    let code: String
}

/// `POST /auth/mfa/setup` → secret shown once; `qrDataUrl` is a `data:image/png;base64,…` URL.
struct MfaSetupResponse: Decodable {
    let secret: String
    let otpauthUrl: String
    let qrDataUrl: String

    /// Raw PNG bytes decoded from the data URL (nil if the server sent something else).
    var qrImageData: Data? {
        guard let comma = qrDataUrl.firstIndex(of: ","),
              qrDataUrl[..<comma].hasSuffix(";base64") else { return nil }
        return Data(base64Encoded: String(qrDataUrl[qrDataUrl.index(after: comma)...]))
    }
}

/// `POST /auth/mfa/enable` → `{ mfaEnabled: true, mfaConfirmedAt }`, `/disable` → `{ mfaEnabled: false }`.
struct MfaStatus: Decodable {
    let mfaEnabled: Bool
}

/// `POST /auth/verify-email` body (token from the verification email).
struct VerifyEmailRequest: Encodable {
    let token: String
}

/// `POST /auth/verify-email` → `{ verified: true, emailVerifiedAt }`.
struct EmailVerified: Decodable {
    let verified: Bool
    let emailVerifiedAt: Date
}

/// `POST /auth/resend-verification` → `{ sent: true, expiresAt }`.
struct VerificationSent: Decodable {
    let sent: Bool
    let expiresAt: Date
}

/// Payment rail modes from `/meta` — each is `"stripe"|"paypal"|"coinbase"|"mock"`.
struct PaymentRails: Decodable, Equatable {
    let card: String
    let klarna: String
    let paypal: String
    let crypto: String
}

/// `GET /v1/meta` → `{ version, paymentMode, rails?, mailer?, aviationProvider, sampleData }`.
/// `rails` and `mailer` arrived with API 0.3; they stay optional so older servers still decode.
struct ServerMeta: Decodable, Equatable {
    let version: String
    let paymentMode: String
    let rails: PaymentRails?
    let mailer: String?
    let aviationProvider: String
    let sampleData: Bool
}
