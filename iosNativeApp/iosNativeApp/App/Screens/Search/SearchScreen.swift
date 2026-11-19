import SwiftUI

/// Global search (repositories / issues & PRs / code / users), shown in the tab bar's search tab.
struct SearchScreen: View {
    enum Results {
        case repositories([RepoSummary])
        case issues([IssueOrPullSummary])
        case code([CodeSearchHit])
        case users([UserSummary])

        var isEmpty: Bool {
            switch self {
            case .repositories(let r): r.isEmpty
            case .issues(let r): r.isEmpty
            case .code(let r): r.isEmpty
            case .users(let r): r.isEmpty
            }
        }
    }

    private struct Request: Hashable {
        var query: String
        var kind: GlobalSearchKind
    }

    @Environment(AppEnvironment.self) private var env
    @State private var text = ""
    @State private var kind: GlobalSearchKind = .repositories
    @State private var submitted: Request?
    @State private var state: LoadState<Results> = .loading

    var body: some View {
        Group {
            if submitted == nil {
                ContentUnavailableView("Search GitHub", systemImage: "magnifyingglass",
                                       description: Text("Find repositories, issues and pull requests, code, and people."))
            } else {
                AsyncContent(state, isEmpty: \.isEmpty, emptyTitle: "No results", emptySystemImage: "magnifyingglass",
                             retry: { await run() }) { results in
                    resultList(results)
                }
            }
        }
        .navigationTitle("Search")
        .searchable(text: $text, prompt: "Search GitHub")
        .searchScopes($kind, activation: .onSearchPresentation) {
            Text("Repositories").tag(GlobalSearchKind.repositories)
            Text("Issues & PRs").tag(GlobalSearchKind.issuesPRs)
            Text("Code").tag(GlobalSearchKind.code)
            Text("Users").tag(GlobalSearchKind.users)
        }
        .onSubmit(of: .search) { submit() }
        .onChange(of: kind) { if submitted != nil { submit() } }
        .task(id: submitted) {
            guard submitted != nil else { return }
            state = .loading
            await run()
        }
    }

    @ViewBuilder
    private func resultList(_ results: Results) -> some View {
        List {
            switch results {
            case .repositories(let repos):
                ForEach(repos) { repo in NavigationLink(value: Route.repo(repo.ref)) { RepoRow(repo: repo) } }
            case .issues(let items):
                ForEach(items) { item in NavigationLink(value: Route.issue(item.ref)) { IssueRow(item: item) } }
            case .code(let hits):
                ForEach(hits) { hit in
                    NavigationLink(value: Route.file(RepoRef(owner: hit.repoOwner, name: hit.repoName), path: hit.path, ref: nil)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(hit.repoFullName).font(.caption).foregroundStyle(.secondary)
                            Text(hit.path).font(.subheadline.monospaced()).lineLimit(2)
                            if let fragment = hit.fragments.first {
                                Text(fragment)
                                    .font(.caption.monospaced())
                                    .lineLimit(4)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentCard(cornerRadius: 8)
                            }
                        }
                    }
                }
            case .users(let users):
                ForEach(users) { user in NavigationLink(value: Route.user(user.login)) { UserRow(user: user) } }
            }
        }
        .listStyle(.plain)
    }

    private func submit() {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        submitted = Request(query: query, kind: kind)
    }

    private func run() async {
        guard let request = submitted else { return }
        await loadState($state) {
            switch request.kind {
            case .repositories: .repositories(try await env.repository.searchRepositories(request.query))
            case .issuesPRs: .issues(try await env.repository.searchIssuesAndPulls(request.query))
            case .code: .code(try await env.repository.searchCode(request.query))
            case .users: .users(try await env.repository.searchUsers(request.query))
            }
        }
    }
}
