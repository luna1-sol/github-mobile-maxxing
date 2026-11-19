import Foundation
import MaxxingShared

/// Swift-facing API of the shared Kotlin core (core/network `GitHubRepository` via `MaxxingCore`).
///
/// All networking, GraphQL/REST parsing, caching, token refresh and error handling run in Kotlin; this type only
/// converts arguments and maps the results to the Swift value types used by the screens. Reads accept
/// `forceRefresh` so pull-to-refresh bypasses the core's in-memory caches.
final class GitHubRepository {
    private let core: MaxxingCore

    init(core: MaxxingCore) {
        self.core = core
    }

    var rateLimit: RateLimitInfo { RateLimitInfo(core.rateLimit) }

    // MARK: Users & activity

    func viewerProfile(forceRefresh: Bool = false) async throws -> ViewerProfile {
        ViewerProfile(try await core.viewerProfile(forceRefresh: forceRefresh))
    }

    func userProfile(_ login: String, forceRefresh: Bool = false) async throws -> UserProfile {
        UserProfile(try await core.userProfile(login: login, forceRefresh: forceRefresh))
    }

    func setFollowing(_ login: String, follow: Bool) async throws {
        try await core.setFollowing(login: login, follow: follow)
    }

    func userRepositories(_ login: String, isOrganization: Bool, forceRefresh: Bool = false) async throws -> [RepoSummary] {
        try await core.userRepositories(login: login, isOrganization: isOrganization, forceRefresh: forceRefresh).map(RepoSummary.init)
    }

    func organizations(_ login: String, forceRefresh: Bool = false) async throws -> [OrganizationSummary] {
        try await core.organizations(login: login, forceRefresh: forceRefresh).map(OrganizationSummary.init)
    }

    func followers(_ login: String, forceRefresh: Bool = false) async throws -> [UserSummary] {
        try await core.followers(login: login, forceRefresh: forceRefresh).map(UserSummary.init)
    }

    func following(_ login: String, forceRefresh: Bool = false) async throws -> [UserSummary] {
        try await core.following(login: login, forceRefresh: forceRefresh).map(UserSummary.init)
    }

    func contributionCalendar(_ login: String, forceRefresh: Bool = false) async throws -> ContributionCalendar {
        ContributionCalendar(try await core.contributionCalendar(login: login, forceRefresh: forceRefresh))
    }

    func receivedEvents(_ login: String, forceRefresh: Bool = false) async throws -> [ActivityEvent] {
        try await core.receivedEvents(login: login, forceRefresh: forceRefresh).map(ActivityEvent.init)
    }

    func userEvents(_ login: String, forceRefresh: Bool = false) async throws -> [ActivityEvent] {
        try await core.userEvents(login: login, forceRefresh: forceRefresh).map(ActivityEvent.init)
    }

    // MARK: Notifications

    func notifications(filter: InboxFilter) async throws -> [NotificationThread] {
        try await core.notifications(all: filter == .all, participating: filter == .participating).map(NotificationThread.init)
    }

    /// Number of unread threads on the first page, used for the Inbox tab badge.
    func unreadNotificationCount() async throws -> Int {
        try await notifications(filter: .unread).filter(\.unread).count
    }

    func markNotificationRead(_ threadID: String) async throws {
        try await core.markNotificationRead(threadId: threadID)
    }

    func markNotificationDone(_ threadID: String) async throws {
        try await core.markNotificationDone(threadId: threadID)
    }

    func markAllNotificationsRead() async throws {
        try await core.markAllNotificationsRead()
    }

    // MARK: Issues & pull requests

    func myIssuesAndPulls(preset: IssueFilterPreset, viewerLogin: String, state: IssueStateFilter,
                          forceRefresh: Bool = false) async throws -> [IssueOrPullSummary] {
        try await core.myIssuesAndPulls(preset: preset.kotlin, viewerLogin: viewerLogin, state: state.kotlin,
                                        forceRefresh: forceRefresh).map(IssueOrPullSummary.init)
    }

    func repoIssuesOrPulls(_ repo: RepoRef, pullRequests: Bool, state: IssueStateFilter,
                           forceRefresh: Bool = false) async throws -> [IssueOrPullSummary] {
        try await core.repoIssuesOrPulls(owner: repo.owner, repo: repo.name, pullRequests: pullRequests, state: state.kotlin,
                                         forceRefresh: forceRefresh).map(IssueOrPullSummary.init)
    }

    func issueOrPullDetail(_ ref: IssueRef, forceRefresh: Bool = false) async throws -> IssueOrPullDetail {
        IssueOrPullDetail(try await core.issueOrPullDetail(owner: ref.owner, repo: ref.repo, number: Int32(ref.number),
                                                           forceRefresh: forceRefresh))
    }

    func pullFiles(_ ref: IssueRef, forceRefresh: Bool = false) async throws -> [PullFileChange] {
        try await core.pullFiles(owner: ref.owner, repo: ref.repo, number: Int32(ref.number), forceRefresh: forceRefresh)
            .map(PullFileChange.init)
    }

    func postComment(_ ref: IssueRef, body: String) async throws {
        try await core.postComment(owner: ref.owner, repo: ref.repo, number: Int32(ref.number), body: body)
    }

    func setState(_ ref: IssueRef, open: Bool) async throws {
        try await core.setIssueOrPullState(owner: ref.owner, repo: ref.repo, number: Int32(ref.number), open: open)
    }

    func createIssue(_ repo: RepoRef, title: String, body: String, labels: [String] = []) async throws -> Int {
        Int(try await core.createIssue(owner: repo.owner, repo: repo.name, title: title, body: body, labels: labels).int32Value)
    }

    func submitReview(_ ref: IssueRef, event: ReviewEvent, body: String) async throws {
        try await core.submitReview(owner: ref.owner, repo: ref.repo, number: Int32(ref.number), event: event.kotlin, body: body)
    }

    func merge(_ ref: IssueRef, method: MergeMethod) async throws {
        try await core.merge(owner: ref.owner, repo: ref.repo, number: Int32(ref.number), method: method.kotlin)
    }

    func setDraft(_ ref: IssueRef, pullRequestID: String, draft: Bool) async throws {
        try await core.setDraft(owner: ref.owner, repo: ref.repo, number: Int32(ref.number), pullRequestId: pullRequestID, draft: draft)
    }

    func toggleReaction(_ ref: IssueRef, subjectID: String, content: String, currentlyReacted: Bool) async throws {
        _ = try await core.toggleReaction(owner: ref.owner, repo: ref.repo, number: Int32(ref.number), subjectId: subjectID,
                                          content: content, currentlyReacted: currentlyReacted)
    }

    func updateComment(_ ref: IssueRef, id: String, body: String) async throws {
        try await core.updateComment(owner: ref.owner, repo: ref.repo, number: Int32(ref.number), commentId: id, body: body)
    }

    func deleteComment(_ ref: IssueRef, id: String) async throws {
        try await core.deleteComment(owner: ref.owner, repo: ref.repo, number: Int32(ref.number), commentId: id)
    }

    func repoLabels(_ repo: RepoRef, forceRefresh: Bool = false) async throws -> [LabelTag] {
        try await core.repoLabels(owner: repo.owner, repo: repo.name, forceRefresh: forceRefresh).map(LabelTag.init)
    }

    // MARK: Repositories

    func viewerRepositories(forceRefresh: Bool = false) async throws -> [RepoSummary] {
        try await core.viewerRepositories(forceRefresh: forceRefresh).map(RepoSummary.init)
    }

    func starredRepositories(forceRefresh: Bool = false) async throws -> [RepoSummary] {
        try await core.starredRepositories(forceRefresh: forceRefresh).map(RepoSummary.init)
    }

    func repoDetail(_ repo: RepoRef, forceRefresh: Bool = false) async throws -> RepoDetail {
        RepoDetail(try await core.repoDetail(owner: repo.owner, repo: repo.name, forceRefresh: forceRefresh))
    }

    func branches(_ repo: RepoRef) async throws -> [BranchRef] {
        try await core.branches(owner: repo.owner, repo: repo.name).map(BranchRef.init)
    }

    func directory(_ repo: RepoRef, path: String, ref: String?, forceRefresh: Bool = false) async throws -> [TreeEntry] {
        try await core.directory(owner: repo.owner, repo: repo.name, path: path, ref: ref, forceRefresh: forceRefresh)
            .map(TreeEntry.init)
    }

    func file(_ repo: RepoRef, path: String, ref: String?, forceRefresh: Bool = false) async throws -> FileContent {
        FileContent(try await core.file(owner: repo.owner, repo: repo.name, path: path, ref: ref, forceRefresh: forceRefresh))
    }

    /// README as raw Markdown, or nil when the repository has none.
    func readme(_ repo: RepoRef, ref: String?, forceRefresh: Bool = false) async throws -> String? {
        try await core.readme(owner: repo.owner, repo: repo.name, ref: ref, forceRefresh: forceRefresh)
    }

    func commits(_ repo: RepoRef, ref: String?, path: String = "", forceRefresh: Bool = false) async throws -> [CommitSummary] {
        try await core.commits(owner: repo.owner, repo: repo.name, ref: ref, path: path, forceRefresh: forceRefresh)
            .map(CommitSummary.init)
    }

    func commitDetail(_ repo: RepoRef, sha: String, forceRefresh: Bool = false) async throws -> CommitDetail {
        CommitDetail(try await core.commitDetail(owner: repo.owner, repo: repo.name, sha: sha, forceRefresh: forceRefresh))
    }

    func setStarred(_ repo: RepoRef, starred: Bool) async throws {
        try await core.setStarred(owner: repo.owner, repo: repo.name, starred: starred)
    }

    func isWatching(_ repo: RepoRef, forceRefresh: Bool = false) async throws -> Bool {
        try await core.isWatching(owner: repo.owner, repo: repo.name, forceRefresh: forceRefresh).boolValue
    }

    func setWatching(_ repo: RepoRef, watching: Bool) async throws {
        try await core.setWatching(owner: repo.owner, repo: repo.name, watching: watching)
    }

    // MARK: Search

    func searchRepositories(_ query: String) async throws -> [RepoSummary] {
        try await core.searchRepositories(query: query, forceRefresh: true).map(RepoSummary.init)
    }

    func searchIssuesAndPulls(_ query: String) async throws -> [IssueOrPullSummary] {
        try await core.searchIssuesAndPulls(query: query, forceRefresh: true).map(IssueOrPullSummary.init)
    }

    func searchCode(_ query: String) async throws -> [CodeSearchHit] {
        try await core.searchCode(query: query, forceRefresh: true).map(CodeSearchHit.init)
    }

    func searchUsers(_ query: String) async throws -> [UserSummary] {
        try await core.searchUsers(query: query, forceRefresh: true).map(UserSummary.init)
    }
}

// MARK: - Swift enum -> Kotlin enum

private extension IssueFilterPreset {
    var kotlin: MaxxingShared.IssueFilterPreset {
        switch self {
        case .created: .created
        case .assigned: .assigned
        case .reviewRequested: .reviewRequested
        case .mentioned: .mentioned
        }
    }
}

private extension IssueStateFilter {
    var kotlin: MaxxingShared.IssueStateFilter {
        switch self {
        case .open: .open
        case .closed: .closed
        case .all: .all
        }
    }
}

private extension ReviewEvent {
    var kotlin: MaxxingShared.ReviewEvent {
        switch self {
        case .approve: .approve
        case .requestChanges: .requestChanges
        case .comment: .comment
        }
    }
}

private extension MergeMethod {
    var kotlin: MaxxingShared.MergeMethod {
        switch self {
        case .squash: .squash
        case .merge: .merge
        case .rebase: .rebase
        }
    }
}
