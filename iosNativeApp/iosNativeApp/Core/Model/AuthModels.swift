import Foundation

// Port of core/model/src/commonMain/kotlin/dev/maxxing/github/model/AuthModels.kt

enum AuthMethod: String, Codable, Sendable {
    case deviceFlow = "DEVICE_FLOW"
    case personalAccessToken = "PERSONAL_ACCESS_TOKEN"
}

struct AuthSession: Codable, Equatable, Sendable {
    var accessToken: String
    var tokenType: String = "bearer"
    var scope: String = ""
    var authMethod: AuthMethod = .deviceFlow
    var userLogin: String?
    /// Single-use token for renewing an expiring OAuth access token; nil for non-expiring tokens and PATs.
    var refreshToken: String?
    /// When `accessToken` stops working (Unix epoch seconds); nil when the token does not expire.
    var accessTokenExpiresAt: Int64?
    /// When `refreshToken` stops working (Unix epoch seconds); nil when unknown or not applicable.
    var refreshTokenExpiresAt: Int64?
    /// The OAuth client id the token was issued to, so it can be refreshed after the client id setting changes.
    var clientID: String?
}

struct RateLimitInfo: Equatable, Sendable {
    var limit = 5000
    var remaining = 5000
    var resetEpochSeconds: Int64 = 0
}
