import SwiftUI

/// Port of the list part of ReposScreen.kt: the viewer's repositories and starred repositories.
struct ReposScreen: View {
    enum Scope: String, CaseIterable, Identifiable {
        case mine, starred
        var id: String { rawValue }
    }

    @Environment(AppEnvironment.self) private var env
    @State private var scope: Scope = .mine
    @State private var mine: LoadState<[RepoSummary]> = .loading
    @State private var starred: LoadState<[RepoSummary]> = .loading
    @State private var filter = ""

    var body: some View {
        let current = scope == .mine ? mine : starred
        AsyncContent(current, emptyTitle: "No repositories", emptySystemImage: "books.vertical", retry: { await load(force: true) }) { repos in
            let shown = filtered(repos)
            List(shown) { repo in
                NavigationLink(value: Route.repo(repo.ref)) { RepoRow(repo: repo) }
                    .swipeActions(edge: .leading) {
                        Button {
                            env.preferences.togglePinned(repo.fullName)
                        } label: {
                            Label(env.preferences.isPinned(repo.fullName) ? "Unpin" : "Pin",
                                  systemImage: env.preferences.isPinned(repo.fullName) ? "pin.slash" : "pin")
                        }
                        .tint(.orange)
                    }
            }
            .listStyle(.plain)
            .overlay {
                if shown.isEmpty { ContentUnavailableView.search(text: filter) }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            FilterChips(selection: $scope, options: Scope.allCases) { scope in
                switch scope {
                case .mine: "My repositories"
                case .starred: "Starred"
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .searchable(text: $filter, placement: .navigationBarDrawer, prompt: "Filter")
        .navigationTitle("Repositories")
        .refreshable { await load(force: true) }
        .task(id: scope) { await load() }
    }

    private func filtered(_ repos: [RepoSummary]) -> [RepoSummary] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return repos }
        return repos.filter {
            $0.fullName.localizedCaseInsensitiveContains(query) || ($0.description?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private func load(force: Bool = false) async {
        switch scope {
        case .mine: await loadState($mine) { try await env.repository.viewerRepositories(forceRefresh: force) }
        case .starred: await loadState($starred) { try await env.repository.starredRepositories(forceRefresh: force) }
        }
    }
}
