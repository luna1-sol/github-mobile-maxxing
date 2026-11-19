import SwiftUI

/// Signed-in shell: a Liquid Glass tab bar with a separate search tab, one `NavigationStack` per tab.
struct MainTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let router = env.router

        TabView(selection: Binding(get: { router.selectedTab }, set: { router.select($0) })) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                stack(.home) { HomeScreen() }
            }
            Tab("Inbox", systemImage: "tray", value: AppTab.inbox) {
                stack(.inbox) { InboxScreen() }
            }
            .badge(env.unreadCount)
            Tab("Issues & PRs", systemImage: "arrow.triangle.pull", value: AppTab.issues) {
                stack(.issues) { IssuesPullsScreen() }
            }
            Tab("Repos", systemImage: "books.vertical", value: AppTab.repos) {
                stack(.repos) { ReposScreen() }
            }
            Tab(value: AppTab.search, role: .search) {
                stack(.search) { SearchScreen() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .task {
            await env.refreshViewer()
            if let url = env.router.pendingURL {
                env.router.pendingURL = nil
                env.router.open(url)
            }
        }
        // Foreground unread polling, tied to the scene phase so it stops in the background.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await env.refreshUnreadCount()
                guard env.preferences.pollUnreadInForeground else { return }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func stack<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack(path: env.router.path(for: tab)) {
            content().appDestinations()
        }
    }
}
