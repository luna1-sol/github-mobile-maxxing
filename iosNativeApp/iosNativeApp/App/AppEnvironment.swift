import SwiftUI
import Observation
import MaxxingShared

/// Object graph of the app (counterpart of composeApp's AppContainer.kt), injected with `.environment`.
@Observable
final class AppEnvironment {
    let preferences: AppPreferences
    let sessionManager: SessionManager
    let repository: GitHubRepository
    let router = AppRouter()

    /// Viewer profile shown in Home and Settings; loaded after sign-in.
    var viewer: ViewerProfile?
    /// Unread notification count for the Inbox tab badge.
    var unreadCount = 0

    init(preferences: AppPreferences = AppPreferences()) {
        // Shared Kotlin core (core/auth + core/network); one instance owns the session and HTTP caches.
        let core = MaxxingCore(defaultClientId: AppBranding.defaultOAuthClientID)
        self.preferences = preferences
        sessionManager = SessionManager(core: core)
        repository = GitHubRepository(core: core)
    }

    var viewerLogin: String? { viewer?.login ?? sessionManager.session?.userLogin }

    func refreshViewer() async {
        if let profile = try? await repository.viewerProfile(forceRefresh: true) { viewer = profile }
    }

    func refreshUnreadCount() async {
        guard sessionManager.isSignedIn, let count = try? await repository.unreadNotificationCount() else { return }
        unreadCount = count
    }

    func signOut() async {
        await sessionManager.signOut()
        preferences.resetAccountState()
        viewer = nil
        unreadCount = 0
        router.reset()
    }
}
