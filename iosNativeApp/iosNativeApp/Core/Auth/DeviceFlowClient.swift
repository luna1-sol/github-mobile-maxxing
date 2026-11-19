import Foundation

/// GitHub OAuth Device Flow (https://docs.github.com/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow),
/// ported from `DeviceFlowClient.kt`. No client secret is needed.
struct DeviceFlowClient: Sendable {
    static let defaultScope = "repo gist notifications read:user user:follow read:org"
    /// Only this device-flow page is accepted as the verification URL, since the UI opens it in a browser.
    static let expectedVerificationURI = "https://github.com/login/device"
    static let requestTimeout: TimeInterval = 15

    struct DeviceCode: Equatable, Sendable {
        var deviceCode: String
        var userCode: String
        var verificationURI: String
        var expiresIn: Int
        var interval: Int
    }

    enum PollResult: Equatable, Sendable {
        case authorized(AuthSession)
        case pending
        case slowDown(newInterval: Int?)
        case expired
        case denied
        case failed(code: String?, description: String)
    }

    enum FlowError: LocalizedError, Equatable {
        case missingClientID
        case codeRequestRejected(status: Int)
        case untrustedVerificationURI(String)
        case network(String)

        var errorDescription: String? {
            switch self {
            case .missingClientID:
                String(localized: "OAuth Client ID is required.")
            case .codeRequestRejected(let status):
                String(localized: "GitHub rejected the device code request (HTTP \(status)). Verify your Client ID.")
            case .untrustedVerificationURI(let uri):
                String(localized: "GitHub returned an unexpected verification URL: \(uri)")
            case .network(let message):
                String(localized: "Failed to contact GitHub: \(message)")
            }
        }
    }

    struct RefreshRejected: LocalizedError {
        var error: String
        var errorDescription: String?
        var isBadRefreshToken: Bool { error == "bad_refresh_token" }
    }

    var githubBaseURL = URL(string: "https://github.com")!
    var apiBaseURL = URL(string: "https://api.github.com")!
    var urlSession: URLSession = .shared
    var now: @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970) }

    // MARK: Device flow

    func requestDeviceCode(clientID rawClientID: String, scope: String = defaultScope) async throws -> DeviceCode {
        let clientID = rawClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else { throw FlowError.missingClientID }
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await postForm(
                githubBaseURL.appending(path: "login/device/code"),
                ["client_id": clientID, "scope": scope]
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw FlowError.network(error.localizedDescription)
        }
        guard response.statusCode == 200 else { throw FlowError.codeRequestRejected(status: response.statusCode) }
        let json = try JSONValue.parse(data)
        guard let deviceCode = json["device_code"]?.string,
              let userCode = json["user_code"]?.string,
              let uri = json["verification_uri"]?.string,
              let expiresIn = json["expires_in"]?.int
        else { throw FlowError.network("Malformed device code response") }
        guard Self.isTrustedVerificationURI(uri) else { throw FlowError.untrustedVerificationURI(uri) }
        return DeviceCode(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURI: uri,
            expiresIn: expiresIn,
            interval: max(json["interval"]?.int ?? 5, 1)
        )
    }

    /// One poll of the token endpoint. Network failures throw so the caller can retry on the next tick.
    func pollAccessToken(clientID: String, deviceCode: String, scope: String = defaultScope) async throws -> PollResult {
        let (data, _) = try await postForm(
            githubBaseURL.appending(path: "login/oauth/access_token"),
            [
                "client_id": clientID,
                "device_code": deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ]
        )
        let json = try JSONValue.parse(data)
        if let token = json["access_token"]?.string, !token.isEmpty {
            let login = await fetchUserLogin(token: token)
            return .authorized(makeSession(from: json, accessToken: token, scope: json["scope"]?.string ?? scope,
                                           clientID: clientID, userLogin: login))
        }
        switch json["error"]?.string {
        case "authorization_pending": return .pending
        case "slow_down": return .slowDown(newInterval: json["interval"]?.int)
        case "expired_token": return .expired
        case "access_denied": return .denied
        case let code:
            return .failed(code: code, description: json["error_description"]?.string ?? code ?? "Unknown OAuth error")
        }
    }

    // MARK: Personal access token

    func verifyPersonalAccessToken(_ raw: String) async throws -> AuthSession {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw GitHubAPIError(statusCode: 400, message: String(localized: "Token cannot be empty"), isSynthetic: true) }
        var request = URLRequest(url: apiBaseURL.appending(path: "user"), timeoutInterval: Self.requestTimeout)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(AppBranding.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw GitHubAPIError(statusCode: status, message: String(localized: "GitHub returned HTTP \(status). Check token scopes."))
        }
        let login = try JSONValue.parse(data)["login"]?.string
        let scopes = http.value(forHTTPHeaderField: "X-OAuth-Scopes")?.trimmingCharacters(in: .whitespaces)
        return AuthSession(
            accessToken: token,
            scope: (scopes?.isEmpty == false ? scopes : nil) ?? "pat",
            authMethod: .personalAccessToken,
            userLogin: login
        )
    }

    // MARK: Refresh

    /// Exchanges the refresh token for a new access/refresh token pair. Both old tokens stop working once
    /// GitHub answers, so the caller must persist the returned session.
    func refresh(_ session: AuthSession) async throws -> AuthSession {
        guard let refreshToken = session.refreshToken, !refreshToken.isEmpty else {
            throw RefreshRejected(error: "no_refresh_token", errorDescription: "Session has no refresh token")
        }
        guard let clientID = session.clientID?.trimmingCharacters(in: .whitespaces), !clientID.isEmpty else {
            throw RefreshRejected(error: "no_client_id", errorDescription: "Session has no OAuth client id to refresh with")
        }
        let (data, response) = try await postForm(
            githubBaseURL.appending(path: "login/oauth/access_token"),
            ["client_id": clientID, "grant_type": "refresh_token", "refresh_token": refreshToken]
        )
        let json = (try? JSONValue.parse(data)) ?? .null
        // GitHub reports OAuth errors with HTTP 200 and an "error" field, so look at the body first.
        if let error = json["error"]?.string {
            throw RefreshRejected(error: error, errorDescription: json["error_description"]?.string)
        }
        guard response.statusCode == 200, let token = json["access_token"]?.string, !token.isEmpty else {
            throw GitHubAPIError(statusCode: response.statusCode, message: "GitHub token refresh failed (HTTP \(response.statusCode))")
        }
        let scope = json["scope"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? session.scope
        var refreshed = makeSession(from: json, accessToken: token, scope: scope, clientID: clientID, userLogin: session.userLogin)
        refreshed.authMethod = session.authMethod
        if json["token_type"]?.string?.isEmpty ?? true { refreshed.tokenType = session.tokenType }
        return refreshed
    }

    // MARK: Helpers

    static func isTrustedVerificationURI(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "github.com",
              components.user == nil, components.password == nil
        else { return false }
        if let port = components.port, port != 443 { return false }
        return components.percentEncodedPath == "/login/device" || components.percentEncodedPath == "/login/device/"
    }

    private func makeSession(from json: JSONValue, accessToken: String, scope: String, clientID: String, userLogin: String?) -> AuthSession {
        let now = now()
        return AuthSession(
            accessToken: accessToken,
            tokenType: json["token_type"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? "bearer",
            scope: scope,
            authMethod: .deviceFlow,
            userLogin: userLogin,
            refreshToken: json["refresh_token"]?.string.flatMap { $0.isEmpty ? nil : $0 },
            accessTokenExpiresAt: json["expires_in"]?.int64.flatMap { $0 > 0 ? now + $0 : nil },
            refreshTokenExpiresAt: json["refresh_token_expires_in"]?.int64.flatMap { $0 > 0 ? now + $0 : nil },
            clientID: clientID
        )
    }

    private func fetchUserLogin(token: String) async -> String? {
        var request = URLRequest(url: apiBaseURL.appending(path: "user"), timeoutInterval: Self.requestTimeout)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(AppBranding.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await urlSession.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONValue.parse(data))?["login"]?.string
    }

    private func postForm(_ url: URL, _ fields: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(AppBranding.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Self.formEncode(fields).data(using: .utf8)
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    static func formEncode(_ fields: [String: String]) -> String {
        // RFC 3986 unreserved characters only (CharacterSet.alphanumerics would let non-ASCII letters through).
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return fields
            .sorted { $0.key < $1.key }
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
    }
}
