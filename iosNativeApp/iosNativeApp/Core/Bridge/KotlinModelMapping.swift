import Foundation
import MaxxingShared

// Maps the Kotlin core models (core/model, exported through the MaxxingShared framework) to the Swift value types
// the SwiftUI screens use. Swift and Kotlin share type names (RepoSummary, IssueRef...), so Kotlin types are always
// written module-qualified as `MaxxingShared.X`.
//
// Kotlin enums are compared by `name`, which is stable and avoids depending on how each case is exported.

private extension Optional where Wrapped == KotlinInt {
    var swiftInt: Int? { self.map { Int($0.int32Value) } }
}

private func nonEmpty(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return value
}

// MARK: - Auth

extension AuthSession {
    init(_ k: MaxxingShared.AuthSession) {
        self.init(
            accessToken: k.accessToken,
            tokenType: k.tokenType,
            scope: k.scope,
            authMethod: k.authMethod.name == "PERSONAL_ACCESS_TOKEN" ? .personalAccessToken : .deviceFlow,
            userLogin: k.userLogin,
            refreshToken: k.refreshToken,
            accessTokenExpiresAt: k.accessTokenExpiresAtEpochSeconds?.int64Value,
            refreshTokenExpiresAt: k.refreshTokenExpiresAtEpochSeconds?.int64Value,
            clientID: k.clientId
        )
    }
}

extension RateLimitInfo {
    init(_ k: MaxxingShared.RateLimitInfo) {
        self.init(limit: Int(k.limit), remaining: Int(k.remaining), resetEpochSeconds: k.resetEpochSeconds)
    }
}

// MARK: - Users

extension UserSummary {
    init(_ k: MaxxingShared.UserSummary) {
        self.init(login: k.login, avatarURL: k.avatarUrl, htmlURL: k.htmlUrl)
    }
}

extension ViewerProfile {
    init(_ k: MaxxingShared.ViewerProfile) {
        self.init(login: k.login, name: nonEmpty(k.name), avatarURL: k.avatarUrl, bio: nonEmpty(k.bio),
                  company: nonEmpty(k.company), location: nonEmpty(k.location),
                  followersCount: Int(k.followersCount), followingCount: Int(k.followingCount),
                  publicReposCount: Int(k.publicReposCount), htmlURL: k.htmlUrl)
    }
}

extension UserProfile {
    init(_ k: MaxxingShared.UserProfile) {
        self.init(login: k.login, name: nonEmpty(k.name), avatarURL: k.avatarUrl, bio: nonEmpty(k.bio),
                  company: nonEmpty(k.company), location: nonEmpty(k.location), blogURL: nonEmpty(k.blogUrl),
                  twitterUsername: nonEmpty(k.twitterUsername), email: nonEmpty(k.email),
                  followersCount: Int(k.followersCount), followingCount: Int(k.followingCount),
                  publicReposCount: Int(k.publicReposCount), publicGistsCount: Int(k.publicGistsCount),
                  isOrganization: k.isOrganization, viewerIsFollowing: k.viewerIsFollowing,
                  createdAt: k.createdAt, htmlURL: k.htmlUrl)
    }
}

extension OrganizationSummary {
    init(_ k: MaxxingShared.OrganizationSummary) {
        self.init(login: k.login, avatarURL: k.avatarUrl, description: nonEmpty(k.description_))
    }
}

// MARK: - Repositories

extension RepoSummary {
    init(_ k: MaxxingShared.RepoSummary) {
        self.init(
            id: k.id, name: k.name, owner: k.owner, fullName: k.fullName,
            description: nonEmpty(k.description_), language: k.language, languageColorHex: k.languageColorHex,
            stargazersCount: Int(k.stargazersCount), forksCount: Int(k.forksCount),
            openIssuesCount: Int(k.openIssuesCount), openPullRequestsCount: k.openPullRequestsCount.swiftInt,
            isPrivate: k.isPrivate, isFork: k.isFork, defaultBranch: k.defaultBranch, updatedAt: k.updatedAt,
            ownerAvatarURL: k.ownerAvatarUrl, viewerHasStarred: k.viewerHasStarred,
            viewerPermission: k.viewerPermission, hasKnownPermission: k.hasKnownPermission,
            isArchived: k.isArchived, hasIssuesEnabled: k.hasIssuesEnabled,
            parent: k.parent.map {
                RepoParentSummary(name: $0.name, owner: $0.owner, fullName: $0.fullName,
                                  defaultBranch: $0.defaultBranch, ownerAvatarURL: $0.ownerAvatarUrl)
            }
        )
    }
}

extension RepoDetail {
    init(_ k: MaxxingShared.RepoDetail) {
        self.init(summary: RepoSummary(k.summary), homepageURL: nonEmpty(k.homepageUrl), licenseName: k.licenseName,
                  topics: k.topics, watchersCount: Int(k.watchersCount))
    }
}

extension BranchRef {
    init(_ k: MaxxingShared.BranchRef) { self.init(name: k.name, sha: k.sha) }
}

extension TreeEntry {
    init(_ k: MaxxingShared.TreeEntry) {
        self.init(path: k.path, name: k.name, type: k.type.name == "TREE" ? .tree : .blob, sha: k.sha, size: k.size)
    }
}

extension FileContent {
    init(_ k: MaxxingShared.FileContent) {
        self.init(path: k.path, name: k.name, size: k.size, content: k.content, isBinary: k.isBinary,
                  htmlURL: k.htmlUrl, sha: k.sha)
    }
}

extension CommitSummary {
    init(_ k: MaxxingShared.CommitSummary) {
        self.init(sha: k.sha, shortSHA: k.shortSha, headline: k.headline, body: k.body, authorName: k.authorName,
                  authorLogin: k.authorLogin, authorAvatarURL: k.authorAvatarUrl, committedAt: k.committedAt,
                  isVerified: k.isVerified)
    }
}

extension CommitDetail {
    init(_ k: MaxxingShared.CommitDetail) {
        self.init(summary: CommitSummary(k.summary), additions: Int(k.additions), deletions: Int(k.deletions),
                  files: k.files.map(PullFileChange.init), htmlURL: k.htmlUrl)
    }
}

// MARK: - Issues & pull requests

extension IssueOrPullKind {
    init(_ k: MaxxingShared.IssueOrPullKind) { self = k.name == "PULL_REQUEST" ? .pullRequest : .issue }
}

extension IssueOrPullState {
    init(_ k: MaxxingShared.IssueOrPullState) { self.init(raw: k.name) }
}

extension LabelTag {
    init(_ k: MaxxingShared.LabelTag) { self.init(name: k.name, colorHex: k.colorHex, description: k.description_) }
}

extension ReactionSummary {
    init(_ k: MaxxingShared.ReactionSummary) {
        self.init(content: k.content, count: Int(k.count), viewerHasReacted: k.viewerHasReacted)
    }
}

extension IssueOrPullSummary {
    init(_ k: MaxxingShared.IssueOrPullSummary) {
        self.init(id: k.id, number: Int(k.number), title: k.title, kind: IssueOrPullKind(k.kind),
                  state: IssueOrPullState(k.state), isDraft: k.isDraft, repoFullName: k.repoFullName,
                  repoOwner: k.repoOwner, repoName: k.repoName, author: UserSummary(k.author),
                  createdAt: k.createdAt, updatedAt: k.updatedAt, commentCount: Int(k.commentCount),
                  labels: k.labels.map(LabelTag.init),
                  checkRollup: k.checkRollup.map { CheckRollupSummary(state: $0.state) },
                  reviewDecision: k.reviewDecision)
    }
}

extension TimelineEvent {
    init?(_ k: any MaxxingShared.TimelineEvent) {
        switch k {
        case let e as MaxxingShared.TimelineEventCommentEvent:
            self = .comment(.init(id: e.id, createdAt: e.createdAt, author: UserSummary(e.author), body: e.body,
                                  authorAssociation: e.authorAssociation, reactions: e.reactions.map(ReactionSummary.init),
                                  viewerCanUpdate: e.viewerCanUpdate, viewerCanDelete: e.viewerCanDelete))
        case let e as MaxxingShared.TimelineEventReviewEventItem:
            self = .review(.init(id: e.id, createdAt: e.createdAt, author: UserSummary(e.author), state: e.state, body: e.body))
        case let e as MaxxingShared.TimelineEventCommitEvent:
            self = .commit(.init(id: e.id, createdAt: e.createdAt, oidShort: e.oidShort,
                                 messageHeadline: e.messageHeadline, authorName: e.authorName))
        case let e as MaxxingShared.TimelineEventStateChangeEvent:
            // GitHubGraphQlService writes English action labels; turn them back into a typed action for localization.
            let action: StateAction
            switch e.actionLabel {
            case "closed this": action = .closed
            case "reopened this": action = .reopened
            case let label where label.hasPrefix("merged into "): action = .merged(into: String(label.dropFirst("merged into ".count)))
            default: return nil
            }
            self = .stateChange(.init(id: e.id, createdAt: e.createdAt, actor: e.actor.map(UserSummary.init), action: action))
        default:
            return nil
        }
    }
}

extension IssueOrPullDetail {
    init(_ k: MaxxingShared.IssueOrPullDetail) {
        let timeline = k.timeline.compactMap(TimelineEvent.init)
        // GitHub records a ClosedEvent alongside every MergedEvent; the web UI shows only the merge, so do the same.
        let isMerged = timeline.contains { if case .stateChange(let c) = $0, case .merged = c.action { true } else { false } }
        let visibleTimeline = isMerged
            ? timeline.filter { if case .stateChange(let c) = $0, c.action == .closed { false } else { true } }
            : timeline
        self.init(
            id: k.id, number: Int(k.number), title: k.title, body: k.body, kind: IssueOrPullKind(k.kind),
            state: IssueOrPullState(k.state), isDraft: k.isDraft, repoOwner: k.repoOwner, repoName: k.repoName,
            author: UserSummary(k.author), createdAt: k.createdAt, updatedAt: k.updatedAt,
            labels: k.labels.map(LabelTag.init), assignees: k.assignees.map(UserSummary.init),
            milestone: k.milestone.map {
                MilestoneSummary(number: Int($0.number), title: $0.title, description: $0.description_,
                                 state: $0.state, dueOn: $0.dueOn)
            },
            headRefName: k.headRefName, baseRefName: k.baseRefName, additions: Int(k.additions),
            deletions: Int(k.deletions), changedFilesCount: Int(k.changedFilesCount), mergeable: k.mergeable,
            mergeStateStatus: k.mergeStateStatus, reviewDecision: k.reviewDecision,
            checkRollup: k.checkRollup.map { CheckRollupSummary(state: $0.state) }, htmlURL: k.htmlUrl,
            timeline: visibleTimeline, viewerPermission: k.viewerPermission, viewerCanUpdate: k.viewerCanUpdate,
            viewerCanCloseOrReopen: k.viewerCanCloseOrReopen, viewerCanMerge: k.viewerCanMerge,
            viewerCanEditMetadata: k.viewerCanEditMetadata, headRefOid: k.headRefOid,
            reactions: k.reactions.map(ReactionSummary.init), requestedReviewers: k.requestedReviewers.map(UserSummary.init)
        )
    }
}

extension PullFileChange {
    init(_ k: MaxxingShared.PullFileChange) {
        self.init(
            filename: k.filename, previousFilename: k.previousFilename,
            status: FileChangeStatus(raw: k.status.name), additions: Int(k.additions), deletions: Int(k.deletions),
            patch: k.patch,
            hunks: k.hunks.map { h in
                DiffHunk(header: h.header, oldStart: Int(h.oldStart), oldCount: Int(h.oldCount),
                         newStart: Int(h.newStart), newCount: Int(h.newCount),
                         lines: h.lines.map { l in
                             let kind: DiffLineKind = switch l.kind.name {
                             case "ADDED": .added
                             case "REMOVED": .removed
                             case "META": .meta
                             default: .context
                             }
                             return DiffLine(kind: kind, content: l.content, oldLineNumber: l.oldLineNumber.swiftInt,
                                             newLineNumber: l.newLineNumber.swiftInt)
                         })
            }
        )
    }
}

// MARK: - Notifications

extension NotificationThread {
    init(_ k: MaxxingShared.NotificationThread) {
        let subjectType: NotificationSubjectType = switch k.subjectType.name {
        case "ISSUE": .issue
        case "PULL_REQUEST": .pullRequest
        case "COMMIT": .commit
        case "RELEASE": .release
        case "DISCUSSION": .discussion
        case "CHECK_SUITE": .checkSuite
        default: .unknown
        }
        self.init(id: k.id, unread: k.unread, reason: NotificationReason(raw: k.reason.name.lowercased()),
                  updatedAt: k.updatedAt, subjectTitle: k.subjectTitle, subjectType: subjectType,
                  subjectURL: k.subjectUrl, latestCommentURL: k.latestCommentUrl, repoFullName: k.repoFullName,
                  repoOwner: k.repoOwner, repoName: k.repoName, repoOwnerAvatarURL: k.repoOwnerAvatarUrl,
                  isPrivate: k.isPrivate)
    }
}

// MARK: - Home

extension ContributionCalendar {
    init(_ k: MaxxingShared.ContributionCalendar) {
        self.init(totalContributions: Int(k.totalContributions), weeks: k.weeks.map { week in
            ContributionWeek(days: week.days.map { ContributionDay(date: $0.date, count: Int($0.count), level: Int($0.level)) })
        })
    }
}

extension ActivityEventKind {
    init(_ k: MaxxingShared.ActivityEventKind) {
        self = switch k.name {
        case "PUSH": .push
        case "PULL_REQUEST": .pullRequest
        case "ISSUES": .issues
        case "ISSUE_COMMENT": .issueComment
        case "PULL_REQUEST_REVIEW": .pullRequestReview
        case "WATCH": .watch
        case "FORK": .fork
        case "CREATE": .create
        case "DELETE": .delete
        case "RELEASE": .release
        case "PUBLIC": .public
        case "MEMBER": .member
        default: .other
        }
    }
}

extension ActivityEvent {
    init(_ k: MaxxingShared.ActivityEvent) {
        let kind = ActivityEventKind(k.kind)
        let number = (k.targetIssueNumber as KotlinInt?).swiftInt
        self.init(id: k.id, kind: kind, actor: UserSummary(k.actor), repoFullName: k.repoFullName,
                  repoOwner: k.repoOwner, repoName: k.repoName,
                  summaryText: ActivitySummary.localized(kind: kind, summary: k.summaryText, number: number,
                                                         branch: k.branchName, releaseTag: k.releaseTag),
                  detailTitle: k.detailTitle, targetIssueNumber: number, commitSHA: k.commitSha,
                  branchName: k.branchName, releaseTag: k.releaseTag, createdAt: k.createdAt)
    }
}

// MARK: - Search

extension CodeSearchHit {
    init(_ k: MaxxingShared.CodeSearchHit) {
        self.init(name: k.name, path: k.path, sha: k.sha, repoFullName: k.repoFullName, repoOwner: k.repoOwner,
                  repoName: k.repoName, htmlURL: k.htmlUrl, fragments: k.fragments)
    }
}
