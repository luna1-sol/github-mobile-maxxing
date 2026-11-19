import SwiftUI

/// Port of HomeScreen.kt: viewer card, contributions, pinned and recent repositories, and the activity feed.
struct HomeScreen: View {
    enum Feed: String, CaseIterable, Identifiable {
        case following, myActivity
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .following: "Following"
            case .myActivity: "My activity"
            }
        }
    }

    @Environment(AppEnvironment.self) private var env
    @State private var calendar: LoadState<ContributionCalendar> = .loading
    @State private var repos: LoadState<[RepoSummary]> = .loading
    @State private var events: LoadState<[ActivityEvent]> = .loading
    @State private var feed: Feed = .following
    @State private var showsSettings = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let viewer = env.viewer {
                    ViewerCard(viewer: viewer)
                }
                if let calendar = calendar.value {
                    ContributionGraph(calendar: calendar)
                }
                pinnedSection
                recentSection
                feedSection
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsSettings = true
                } label: {
                    if let avatar = env.viewer?.avatarURL, !avatar.isEmpty {
                        AvatarView(url: avatar, size: 30)
                    } else {
                        Image(systemName: "gearshape")
                    }
                }
                .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $showsSettings) { SettingsScreen() }
        .refreshable { await reload() }
        // Separate tasks so the three requests run concurrently on first appearance.
        .task(id: env.viewerLogin) { await loadRepos() }
        .task(id: env.viewerLogin) { await loadCalendar() }
        .task(id: FeedKey(login: env.viewerLogin, feed: feed)) { await loadFeed() }
    }

    // MARK: Sections

    @ViewBuilder
    private var pinnedSection: some View {
        let pinned = env.preferences.pinnedRepos
        if !pinned.isEmpty {
            SectionHeader("Pinned")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(pinned, id: \.self) { fullName in
                        let parts = fullName.split(separator: "/", maxSplits: 1).map(String.init)
                        if parts.count == 2 {
                            NavigationLink(value: Route.repo(RepoRef(owner: parts[0], name: parts[1]))) {
                                Label(fullName, systemImage: "pin.fill")
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            .glassCapsule()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        if let recent = repos.value, !recent.isEmpty {
            SectionHeader("Recent repositories")
            VStack(spacing: 0) {
                ForEach(recent.prefix(5)) { repo in
                    NavigationLink(value: Route.repo(repo.ref)) {
                        RepoRow(repo: repo)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if repo.id != recent.prefix(5).last?.id { Divider().padding(.leading, 62) }
                }
            }
            .contentCard()
        }
    }

    @ViewBuilder
    private var feedSection: some View {
        SectionHeader("Activity")
        Picker("Feed", selection: $feed) {
            ForEach(Feed.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)

        AsyncContent(events, emptyTitle: "No recent activity", emptySystemImage: "bolt.horizontal",
                     retry: { await loadFeed() }) { events in
            VStack(spacing: 0) {
                ForEach(events) { event in
                    ActivityRow(event: event)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    if event.id != events.last?.id { Divider().padding(.leading, 56) }
                }
            }
            .contentCard()
        }
        .frame(minHeight: 160)
    }

    // MARK: Loading

    private struct FeedKey: Hashable {
        var login: String?
        var feed: Feed
    }

    private func reload() async {
        await loadRepos()
        await loadCalendar()
        await loadFeed(keepCurrent: true)
    }

    private func loadRepos() async {
        guard env.viewerLogin != nil else { return }
        await loadState($repos) { try await env.repository.viewerRepositories() }
    }

    private func loadCalendar() async {
        guard let login = env.viewerLogin else { return }
        await loadState($calendar) { try await env.repository.contributionCalendar(login) }
    }

    private func loadFeed(keepCurrent: Bool = false) async {
        guard let login = env.viewerLogin else { return }
        // Switching feeds must not show the other feed's events while loading.
        if !keepCurrent { events = .loading }
        let feed = feed
        await loadState($events) {
            switch feed {
            case .following: try await env.repository.receivedEvents(login)
            case .myActivity: try await env.repository.userEvents(login)
            }
        }
    }
}

struct SectionHeader: View {
    let title: LocalizedStringKey
    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title)
            .font(.title3.bold())
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct ViewerCard: View {
    let viewer: ViewerProfile

    var body: some View {
        NavigationLink(value: Route.user(viewer.login)) {
            HStack(spacing: 14) {
                AvatarView(url: viewer.avatarURL, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewer.name ?? viewer.login).font(.title3.bold())
                    if viewer.name != nil { Text(viewer.login).foregroundStyle(.secondary) }
                    HStack(spacing: 12) {
                        Label("\(Formatting.compact(viewer.followersCount)) followers", systemImage: "person.2")
                        Label("\(Formatting.compact(viewer.publicReposCount)) repos", systemImage: "book.closed")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(16)
            .contentCard()
        }
        .buttonStyle(.plain)
    }
}

struct ContributionGraph: View {
    let calendar: ContributionCalendar

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(calendar.totalContributions) contributions in the last year")
                .font(.subheadline.weight(.semibold))
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 3) {
                        ForEach(Array(calendar.weeks.enumerated()), id: \.offset) { index, week in
                            VStack(spacing: 3) {
                                ForEach(week.days, id: \.date) { day in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(color(for: day.level))
                                        .frame(width: 11, height: 11)
                                        .accessibilityLabel(Text("\(day.count) contributions on \(day.date)"))
                                }
                            }
                            .id(index)
                        }
                    }
                }
                .onAppear { proxy.scrollTo(calendar.weeks.count - 1, anchor: .trailing) }
            }
            HStack(spacing: 4) {
                Spacer()
                Text("Less").font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 2).fill(color(for: level)).frame(width: 10, height: 10)
                }
                Text("More").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .contentCard()
    }

    private func color(for level: Int) -> Color {
        level == 0 ? Color.secondary.opacity(0.15) : Color.accentColor.opacity(0.25 + Double(level) * 0.18)
    }
}

struct ActivityRow: View {
    let event: ActivityEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NavigationLink(value: Route.user(event.actor.login)) {
                AvatarView(url: event.actor.avatarURL, size: 32)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Text(event.actor.login).bold()) \(event.summaryText)")
                    .font(.subheadline)
                NavigationLink(value: destination) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.repoFullName).font(.subheadline.weight(.medium)).foregroundStyle(.tint)
                        if let detail = event.detailTitle, !detail.isEmpty {
                            Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
                .buttonStyle(.plain)
                Text(Formatting.relative(event.createdAt)).font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
    }

    private var destination: Route {
        if let number = event.targetIssueNumber {
            return .issue(IssueRef(owner: event.repoOwner, repo: event.repoName, number: number))
        }
        if event.kind == .push, let sha = event.commitSHA {
            return .commit(event.repoRef, sha: sha)
        }
        return .repo(event.repoRef)
    }

    private var symbol: String {
        switch event.kind {
        case .push: "arrow.up.circle"
        case .pullRequest, .pullRequestReview: "arrow.triangle.pull"
        case .issues: "circle.circle"
        case .issueComment: "bubble.left"
        case .watch: "star"
        case .fork: "tuningfork"
        case .create: "plus.circle"
        case .delete: "trash"
        case .release: "tag"
        case .public: "globe"
        case .member: "person.badge.plus"
        case .other: "bolt"
        }
    }
}
