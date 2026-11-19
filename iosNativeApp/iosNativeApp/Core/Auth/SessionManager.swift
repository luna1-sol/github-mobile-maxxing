import Foundation
import Observation

/// Owns the signed-in session (port of `SessionManager.kt`): loads/saves it in the Keychain and refreshes
/// expiring OAuth tokens, once ahead of expiry and once more after an HTTP 401.
@Observable
final class SessionManager {
    /// Refresh an expiring access token this many seconds before it expires.
    static let proactiveRefreshWindow: Int64 = 5 * 60
    /// After a refresh fails for a reason other than a rejected refresh token, wait this long before retrying.
    static let refreshRetryBackoff: Int64 = 30

    private(set) var session: AuthSession?
    private(set) var isLoaded = false
    /// Set when the Keychain could not be read; the UI offers a retry instead of the sign-in screen.
    private(set) var loadError: String?

    @ObservationIgnored private let keychain: KeychainTokenStore
    @ObservationIgnored private let deviceFlow: DeviceFlowClient
    @ObservationIgnored private var refreshTask: Task<AuthSession?, Never>?
    /// Refresh token -> epoch second before which it is not sent again (`Int64.max` once GitHub rejected it).
    @ObservationIgnored private var refreshRetryNotBefore: [String: Int64] = [:]

    init(keychain: KeychainTokenStore = .session, deviceFlow: DeviceFlowClient = DeviceFlowClient()) {
        self.keychain = keychain
        self.deviceFlow = deviceFlow
    }

    var isSignedIn: Bool { session != nil }

    func load() {
        do {
            if let data = try keychain.read() {
                session = try? JSONDecoder().decode(AuthSession.self, from: data)
            }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        isLoaded = true
    }

    func signIn(_ newSession: AuthSession) throws {
        try persist(newSession)
        session = newSession
    }

    func signOut() async {
        // Wait for an in-flight token refresh so it cannot save the session again after it was cleared.
        _ = await refreshTask?.value
        try? keychain.delete()
        session = nil
        refreshRetryNotBefore = [:]
    }

    // MARK: Token access used by GitHubHttpClient

    /// The access token to send, refreshed first when it expires within `proactiveRefreshWindow`.
    func validAccessToken() async -> String? {
        guard let current = session else { return nil }
        guard current.refreshToken?.isEmpty == false, isExpiringSoon(current) else { return current.accessToken }
        return await refresh(failedAccessToken: current.accessToken, onlyIfExpiringSoon: true)?.accessToken
            ?? session?.accessToken
    }

    /// Called after HTTP 401 for `rejectedToken`. Returns a different token when one could be obtained.
    func tokenAfterUnauthorized(_ rejectedToken: String) async -> String? {
        guard let refreshed = await refresh(failedAccessToken: rejectedToken, onlyIfExpiringSoon: false),
              refreshed.accessToken != rejectedToken else { return nil }
        return refreshed.accessToken
    }

    private func refresh(failedAccessToken: String, onlyIfExpiringSoon: Bool) async -> AuthSession? {
        if let running = refreshTask { return await running.value }
        guard let stored = session else { return nil }
        if stored.accessToken != failedAccessToken { return stored }
        if onlyIfExpiringSoon && !isExpiringSoon(stored) { return stored }
        if isRefreshTokenUnusable(stored) { return nil }

        // Unstructured on purpose: GitHub invalidates the old refresh token as soon as it answers, so the new
        // pair must be stored even if the request that triggered the refresh is cancelled meanwhile.
        let task = Task<AuthSession?, Never> { [deviceFlow] in
            do {
                let refreshed = try await deviceFlow.refresh(stored)
                self.session = refreshed
                if let old = stored.refreshToken { self.refreshRetryNotBefore[old] = nil }
                try? self.persist(refreshed)
                return refreshed
            } catch {
                if let old = stored.refreshToken {
                    let rejected = (error as? DeviceFlowClient.RefreshRejected) != nil
                    self.refreshRetryNotBefore[old] = rejected ? .max : self.now() + Self.refreshRetryBackoff
                }
                return nil
            }
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    private func isRefreshTokenUnusable(_ session: AuthSession) -> Bool {
        guard let token = session.refreshToken, !token.isEmpty else { return true }
        let now = now()
        if let expiresAt = session.refreshTokenExpiresAt, expiresAt <= now { return true }
        guard let retryAt = refreshRetryNotBefore[token] else { return false }
        if retryAt == .max { return true }
        // A clock that jumped backwards must not stretch the pause.
        return now < retryAt && retryAt - now <= Self.refreshRetryBackoff
    }

    private func isExpiringSoon(_ session: AuthSession) -> Bool {
        guard let expiresAt = session.accessTokenExpiresAt else { return false }
        return expiresAt - now() <= Self.proactiveRefreshWindow
    }

    private func persist(_ session: AuthSession) throws {
        try keychain.write(JSONEncoder().encode(session))
    }

    private func now() -> Int64 { deviceFlow.now() }
}
