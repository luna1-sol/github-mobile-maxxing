import SwiftUI
import Observation

/// Object graph of the app (counterpart of composeApp's AppContainer.kt), injected with `.environment`.
@Observable
final class AppEnvironment {
    let preferences: AppPreferences
    let sessionManager: SessionManager
    let httpClient: GitHubHttpClient
    let repository: GitHubRepository
    let router = AppRouter()

    /// Viewer profile shown in Home and Settings; loaded after sign-in.
    var viewer: ViewerProfile?
    /// Unread notification count for the Inbox tab badge.
    var unreadCount = 0

    init(preferences: AppPreferences = AppPreferences(), sessionManager: SessionManager = SessionManager()) {
        self.preferences = preferences
        self.sessionManager = sessionManager
        httpClient = GitHubHttpClient(sessionManager: sessionManager)
        repository = GitHubRepository(client: httpClient)
    }

    var viewerLogin: String? { viewer?.login ?? sessionManager.session?.userLogin }

    func refreshViewer() async {
        if let profile = try? await repository.viewerProfile() { viewer = profile }
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
