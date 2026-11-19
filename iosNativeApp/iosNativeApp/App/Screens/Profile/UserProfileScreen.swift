import SwiftUI

/// Port of UserProfileScreen.kt: profile header, follow, organizations, contributions, repositories and activity.
struct UserProfileScreen: View {
    let login: String

    enum Tab: String, CaseIterable, Identifiable {
        case repositories, activity
        var id: String { rawValue }
    }

    @Environment(AppEnvironment.self) private var env
    @State private var profile: LoadState<UserProfile> = .loading
    @State private var repos: LoadState<[RepoSummary]> = .loading
    @State private var events: LoadState<[ActivityEvent]> = .loading
    @State private var orgs: [OrganizationSummary] = []
    @State private var calendar: ContributionCalendar?
    @State private var tab: Tab = .repositories
    @State private var isUpdatingFollow = false
    @State private var error: String?

    var body: some View {
        AsyncContent(profile, retry: { await load(force: true) }) { user in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    header(user)
                    if !orgs.isEmpty { orgStrip }
                    if let calendar { ContributionGraph(calendar: calendar) }
                    Picker("Section", selection: $tab) {
                        Text("Repositories").tag(Tab.repositories)
                        Text("Activity").tag(Tab.activity)
                    }
                    .pickerStyle(.segmented)
                    switch tab {
                    case .repositories: repoList
                    case .activity: activityList
                    }
                }
                .padding()
            }
            .refreshable { await load(force: true) }
        }
        .navigationTitle(login)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = URL(string: "https://github.com/\(login)") {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ShareLink(item: url)
                        Button("Open in browser", systemImage: "safari") { env.router.openExternally(url) }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More actions")
                }
            }
        }
        .task(id: login) { await load() }
        .errorAlert($error)
    }

    private func header(_ user: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                AvatarView(url: user.avatarURL, size: 76, isOrganization: user.isOrganization)
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.name ?? user.login).font(.title2.bold())
                    if user.name != nil { Text(user.login).foregroundStyle(.secondary) }
                }
            }
            if let bio = user.bio { Text(bio) }
            VStack(alignment: .leading, spacing: 6) {
                if let company = user.company { Label(company, systemImage: "building.2") }
                if let location = user.location { Label(location, systemImage: "mappin.and.ellipse") }
                if let blog = user.blogURL, let url = URL(string: blog.hasPrefix("http") ? blog : "https://\(blog)") {
                    Link(destination: url) { Label(blog, systemImage: "link") }
                }
                if let twitter = user.twitterUsername { Label("@\(twitter)", systemImage: "at") }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    if !user.isOrganization {
                        NavigationLink(value: Route.users(login: user.login, following: false)) {
                            Text("\(Text(Formatting.compact(user.followersCount)).bold()) followers")
                        }
                        .buttonStyle(.glass)
                        NavigationLink(value: Route.users(login: user.login, following: true)) {
                            Text("\(Text(Formatting.compact(user.followingCount)).bold()) following")
                        }
                        .buttonStyle(.glass)
                    }
                    Spacer(minLength: 0)
                    if !user.isOrganization, user.login.caseInsensitiveCompare(env.viewerLogin ?? "") != .orderedSame {
                        Button {
                            Task { await toggleFollow(user) }
                        } label: {
                            if isUpdatingFollow {
                                ProgressView()
                            } else {
                                Text(user.viewerIsFollowing ? "Unfollow" : "Follow")
                            }
                        }
                        .buttonStyle(user.viewerIsFollowing ? AnyPrimitiveButtonStyle(.glass) : AnyPrimitiveButtonStyle(.glassProminent))
                        .disabled(isUpdatingFollow)
                    }
                }
            }
            .font(.subheadline)
        }
    }

    private var orgStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(orgs) { org in
                    NavigationLink(value: Route.user(org.login)) {
                        AvatarView(url: org.avatarURL, size: 36, isOrganization: true)
                    }
                    .accessibilityLabel(org.login)
                }
            }
        }
    }

    private var repoList: some View {
        AsyncContent(repos, emptyTitle: "No public repositories", emptySystemImage: "books.vertical") { repos in
            VStack(spacing: 0) {
                ForEach(repos) { repo in
                    NavigationLink(value: Route.repo(repo.ref)) {
                        RepoRow(repo: repo)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if repo.id != repos.last?.id { Divider().padding(.leading, 62) }
                }
            }
            .contentCard()
        }
        .frame(minHeight: 120)
    }

    private var activityList: some View {
        AsyncContent(events, emptyTitle: "No recent activity", emptySystemImage: "bolt.horizontal") { events in
            VStack(spacing: 0) {
                ForEach(events) { event in
                    ActivityRow(event: event).padding(.horizontal, 14).padding(.vertical, 10)
                    if event.id != events.last?.id { Divider().padding(.leading, 56) }
                }
            }
            .contentCard()
        }
        .frame(minHeight: 120)
    }

    private func load(force: Bool = false) async {
        await loadState($profile) { try await env.repository.userProfile(login, forceRefresh: force) }
        guard let user = profile.value else { return }
        await loadState($repos) { try await env.repository.userRepositories(login, isOrganization: user.isOrganization, forceRefresh: force) }
        if !user.isOrganization {
            orgs = (try? await env.repository.organizations(login, forceRefresh: force)) ?? []
            calendar = try? await env.repository.contributionCalendar(login, forceRefresh: force)
        }
        await loadState($events) { try await env.repository.userEvents(login, forceRefresh: force) }
    }

    private func toggleFollow(_ user: UserProfile) async {
        isUpdatingFollow = true
        defer { isUpdatingFollow = false }
        do {
            try await env.repository.setFollowing(user.login, follow: !user.viewerIsFollowing)
            var updated = user
            updated.viewerIsFollowing.toggle()
            updated.followersCount += updated.viewerIsFollowing ? 1 : -1
            profile = .loaded(updated)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct UserListScreen: View {
    let login: String
    let following: Bool

    @Environment(AppEnvironment.self) private var env
    @State private var state: LoadState<[UserSummary]> = .loading

    var body: some View {
        AsyncContent(state, emptyTitle: following ? "Not following anyone" : "No followers", emptySystemImage: "person.2",
                     retry: { await load(force: true) }) { users in
            List(users) { user in
                NavigationLink(value: Route.user(user.login)) { UserRow(user: user) }
            }
            .listStyle(.plain)
        }
        .navigationTitle(following ? "Following" : "Followers")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load(force: Bool = false) async {
        await loadState($state) {
            if following {
                return try await env.repository.following(login, forceRefresh: force)
            } else {
                return try await env.repository.followers(login, forceRefresh: force)
            }
        }
    }
}
