import SwiftUI

/// Port of the repository detail in ReposScreen.kt: header, star/watch, branch switcher, sections and README.
struct RepoDetailScreen: View {
    let repo: RepoRef

    @Environment(AppEnvironment.self) private var env
    @State private var detail: LoadState<RepoDetail> = .loading
    @State private var readme: LoadState<String?> = .loading
    @State private var branches: [BranchRef] = []
    @State private var selectedRef: String?
    @State private var isWatching: Bool?
    @State private var showsNewIssue = false
    @State private var error: String?
    @Namespace private var glassNamespace

    private var ref: String? { selectedRef ?? detail.value?.summary.defaultBranch }

    var body: some View {
        AsyncContent(detail, retry: { await load() }) { detail in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(detail)
                    actionBar(detail.summary)
                    sections(detail.summary)
                    readmeSection(detail.summary)
                }
                .padding()
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .refreshable { await load() }
        }
        .navigationTitle(repo.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: repo.webURL)
                    Button("Open in browser", systemImage: "safari") { env.router.openExternally(repo.webURL) }
                    Button("Copy URL", systemImage: "link") { UIPasteboard.general.url = repo.webURL }
                    Divider()
                    Button(env.preferences.isPinned(repo.fullName) ? "Unpin from Home" : "Pin to Home",
                           systemImage: env.preferences.isPinned(repo.fullName) ? "pin.slash" : "pin") {
                        env.preferences.togglePinned(repo.fullName)
                    }
                    if detail.value.map({ RepoCapabilities.resolve($0.summary, viewerLogin: env.viewerLogin).canCreateIssue }) ?? false {
                        Button("New issue", systemImage: "plus.circle") { showsNewIssue = true }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More actions")
            }
        }
        .sheet(isPresented: $showsNewIssue) {
            NewIssueSheet(repo: repo) { number in
                env.router.push(.issue(IssueRef(owner: repo.owner, repo: repo.name, number: number)))
            }
        }
        .task(id: repo) { await load() }
        .task(id: ref) { await loadReadme() }
        .errorAlert($error)
    }

    // MARK: Sections

    private func header(_ detail: RepoDetail) -> some View {
        let summary = detail.summary
        return VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: Route.user(summary.owner)) {
                HStack(spacing: 8) {
                    AvatarView(url: summary.ownerAvatarURL, size: 24)
                    Text(summary.owner).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                Text(summary.name).font(.title.bold())
                if summary.isPrivate { Label("Private", systemImage: "lock.fill").labelStyle(.iconOnly).foregroundStyle(.secondary) }
                if summary.isArchived {
                    Text("Archived").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 2)
                        .background(.orange.opacity(0.2), in: .capsule)
                }
            }
            if let parent = summary.parent {
                NavigationLink(value: Route.repo(RepoRef(owner: parent.owner, name: parent.name))) {
                    Label("Forked from \(parent.fullName)", systemImage: "tuningfork").font(.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
            if let description = summary.description, !description.isEmpty {
                Text(description)
            }
            if let homepage = detail.homepageURL, let url = URL(string: homepage) {
                Link(destination: url) { Label(homepage, systemImage: "link").lineLimit(1) }.font(.footnote)
            }
            if !detail.topics.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(detail.topics, id: \.self) { topic in
                        Text(topic).font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12), in: .capsule)
                            .foregroundStyle(.tint)
                    }
                }
            }
            HStack(spacing: 14) {
                StatLabel(systemImage: "star", value: summary.stargazersCount)
                StatLabel(systemImage: "tuningfork", value: summary.forksCount)
                StatLabel(systemImage: "eye", value: detail.watchersCount)
                if let language = summary.language { LanguageDot(name: language, colorHex: summary.languageColorHex) }
                if let license = detail.licenseName { Label(license, systemImage: "scalemass").lineLimit(1) }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    /// Star / watch / branch controls as one Liquid Glass group.
    private func actionBar(_ summary: RepoSummary) -> some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    Task { await toggleStar(summary) }
                } label: {
                    Label(summary.viewerHasStarred ? "Starred" : "Star", systemImage: summary.viewerHasStarred ? "star.fill" : "star")
                }
                .buttonStyle(summary.viewerHasStarred ? AnyPrimitiveButtonStyle(.glassProminent) : AnyPrimitiveButtonStyle(.glass))
                .glassEffectID("star", in: glassNamespace)

                Button {
                    Task { await toggleWatch() }
                } label: {
                    Label(isWatching == true ? "Watching" : "Watch", systemImage: isWatching == true ? "eye.fill" : "eye")
                }
                .buttonStyle(.glass)
                .disabled(isWatching == nil)
                .glassEffectID("watch", in: glassNamespace)

                Menu {
                    Picker("Branch", selection: Binding(get: { ref ?? summary.defaultBranch }, set: { selectedRef = $0 })) {
                        ForEach(branches) { branch in Text(branch.name).tag(branch.name) }
                    }
                } label: {
                    Label(ref ?? summary.defaultBranch, systemImage: "arrow.triangle.branch")
                        .lineLimit(1)
                }
                .buttonStyle(.glass)
                .glassEffectID("branch", in: glassNamespace)
            }
        }
    }

    private func sections(_ summary: RepoSummary) -> some View {
        VStack(spacing: 0) {
            sectionLink(.directory(repo, path: "", ref: ref), title: "Code", systemImage: "chevron.left.forwardslash.chevron.right", count: nil)
            Divider().padding(.leading, 52)
            if summary.hasIssuesEnabled {
                sectionLink(.repoIssues(repo, pullRequests: false), title: "Issues", systemImage: "circle.circle", count: summary.openIssuesCount)
                Divider().padding(.leading, 52)
            }
            sectionLink(.repoIssues(repo, pullRequests: true), title: "Pull requests", systemImage: "arrow.triangle.pull",
                        count: summary.openPullRequestsCount)
            Divider().padding(.leading, 52)
            sectionLink(.commits(repo, ref: ref), title: "Commits", systemImage: "clock.arrow.circlepath", count: nil)
        }
        .contentCard()
    }

    private func sectionLink(_ route: Route, title: LocalizedStringKey, systemImage: String, count: Int?) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 14) {
                Image(systemName: systemImage).foregroundStyle(.tint).frame(width: 24)
                Text(title)
                Spacer()
                if let count { Text(Formatting.compact(count)).foregroundStyle(.secondary) }
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func readmeSection(_ summary: RepoSummary) -> some View {
        switch readme {
        case .loaded(let text?):
            VStack(alignment: .leading, spacing: 12) {
                Label("README", systemImage: "book").font(.headline)
                MarkdownView(markdown: text, context: MarkdownContext(repo: repo, ref: ref ?? summary.defaultBranch))
            }
            .padding(16)
            .contentCard()
        case .loading:
            ProgressView().frame(maxWidth: .infinity).padding()
        default:
            EmptyView()
        }
    }

    // MARK: Loading & actions

    private func load() async {
        await loadState($detail) { try await env.repository.repoDetail(repo) }
        if let list = try? await env.repository.branches(repo) { branches = list }
        isWatching = try? await env.repository.isWatching(repo)
    }

    private func loadReadme() async {
        guard detail.value != nil else { return }
        readme = .loading
        let ref = ref
        await loadState($readme) { try await env.repository.readme(repo, ref: ref) }
    }

    private func toggleStar(_ summary: RepoSummary) async {
        guard case .loaded(var current) = detail else { return }
        let starred = !summary.viewerHasStarred
        current.summary.viewerHasStarred = starred
        current.summary.stargazersCount += starred ? 1 : -1
        detail = .loaded(current)
        do {
            try await env.repository.setStarred(repo, starred: starred)
        } catch {
            current.summary.viewerHasStarred = !starred
            current.summary.stargazersCount -= starred ? 1 : -1
            detail = .loaded(current)
            self.error = error.localizedDescription
        }
    }

    private func toggleWatch() async {
        guard let watching = isWatching else { return }
        isWatching = !watching
        do {
            try await env.repository.setWatching(repo, watching: !watching)
        } catch {
            isWatching = watching
            self.error = error.localizedDescription
        }
    }
}

/// Type-erased button style so a button can switch between `.glass` and `.glassProminent`.
struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: PrimitiveButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}
