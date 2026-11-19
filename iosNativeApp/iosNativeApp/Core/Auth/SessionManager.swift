import Foundation
import Observation
import MaxxingShared

/// Observable view of the shared Kotlin `SessionManager` (core/auth): Keychain storage, Device Flow, PAT sign-in and
/// OAuth token refresh all run in Kotlin. This type exposes the current session to SwiftUI.
@Observable
final class SessionManager {
    private(set) var session: AuthSession?
    private(set) var isLoaded = false
    /// Set when the Keychain could not be read; the UI offers a retry instead of the sign-in screen.
    private(set) var loadError: String?

    @ObservationIgnored let core: MaxxingCore
    @ObservationIgnored private var sessionObservation: Cancellable?

    init(core: MaxxingCore) {
        self.core = core
    }

    var isSignedIn: Bool { session != nil }

    func load() async {
        do {
            try await core.initialize()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        if sessionObservation == nil {
            sessionObservation = core.observeSession { [weak self] session in
                self?.session = session.map(AuthSession.init)
            }
        }
        session = core.currentSession.map(AuthSession.init)
        isLoaded = true
    }

    func signIn(personalAccessToken token: String) async throws {
        _ = try await core.signInWithPat(token: token)
    }

    func signOut() async {
        try? await core.signOut()
    }
}
