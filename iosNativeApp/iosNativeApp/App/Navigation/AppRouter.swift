import SwiftUI
import Observation

enum AppTab: String, Hashable, CaseIterable {
    case home, inbox, issues, repos, search
}

/// Pushable destinations inside a tab's `NavigationStack`.
enum Route: Hashable {
    case repo(RepoRef)
    case issue(IssueRef)
    case user(String)
    case directory(RepoRef, path: String, ref: String?)
    case file(RepoRef, path: String, ref: String?)
    case commits(RepoRef, ref: String?)
    case commit(RepoRef, sha: String)
    case repoIssues(RepoRef, pullRequests: Bool)
    case pullFiles(IssueRef)
    case users(login: String, following: Bool)
}

/// Owns tab selection and per-tab navigation paths so deep links and GitHub URLs can navigate from anywhere.
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var paths: [AppTab: [Route]] = [:]
    /// External page shown in an in-app Safari sheet.
    var safariURL: URL?
    /// Deep link received before sign-in; applied once the main UI appears.
    var pendingURL: URL?

    func path(for tab: AppTab) -> Binding<[Route]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }

    func push(_ route: Route) {
        paths[selectedTab, default: []].append(route)
    }

    /// Selecting the current tab again pops it to the root, like UIKit tab bars.
    func select(_ tab: AppTab) {
        if tab == selectedTab { paths[tab] = [] }
        selectedTab = tab
    }

    func reset() {
        selectedTab = .home
        paths = [:]
        safariURL = nil
    }

    /// Handles `githubmaxxing-native://` and `https://github.com/...` URLs in-app. Returns false for URLs it does not own.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let link = GitHubUrlParser.parse(url) else { return false }
        switch link {
        case .issueOrPull(let ref, let fromNotification):
            if fromNotification {
                selectedTab = .inbox
                paths[.inbox] = [.issue(ref)]
            } else {
                push(.issue(ref))
            }
        case .repository(let repo):
            push(.repo(repo))
        case .user(let login):
            push(.user(login))
        case .externalWeb(let url):
            safariURL = url
        }
        return true
    }

    /// Opens a URL the app cannot show natively in an in-app browser sheet.
    func openExternally(_ url: URL) {
        guard url.scheme == "https" || url.scheme == "http" else { return }
        safariURL = url
    }
}

extension View {
    /// Registers every `Route` destination; apply inside each tab's `NavigationStack`.
    func appDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .repo(let repo): RepoDetailScreen(repo: repo)
            case .issue(let ref): IssuePullDetailScreen(ref: ref)
            case .user(let login): UserProfileScreen(login: login)
            case .directory(let repo, let path, let ref): DirectoryScreen(repo: repo, path: path, ref: ref)
            case .file(let repo, let path, let ref): FileScreen(repo: repo, path: path, ref: ref)
            case .commits(let repo, let ref): CommitsScreen(repo: repo, ref: ref)
            case .commit(let repo, let sha): CommitDetailScreen(repo: repo, sha: sha)
            case .repoIssues(let repo, let pullRequests): RepoIssuesScreen(repo: repo, pullRequests: pullRequests)
            case .pullFiles(let ref): PullFilesScreen(ref: ref)
            case .users(let login, let following): UserListScreen(login: login, following: following)
            }
        }
    }
}
