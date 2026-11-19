import Foundation

// Port of core/model/src/commonMain/kotlin/dev/maxxing/github/model/HomeModels.kt

struct ContributionDay: Hashable, Sendable {
    var date: String
    var count: Int
    /// 0...4
    var level: Int
}

struct ContributionWeek: Hashable, Sendable {
    var days: [ContributionDay]
}

struct ContributionCalendar: Hashable, Sendable {
    var totalContributions: Int
    var weeks: [ContributionWeek]
}

enum ActivityEventKind: Hashable, Sendable {
    case push, pullRequest, issues, issueComment, pullRequestReview, watch, fork, create, delete, release, `public`, member, other
}

struct ActivityEvent: Hashable, Sendable, Identifiable {
    var id: String
    var kind: ActivityEventKind
    var actor: UserSummary
    var repoFullName: String
    var repoOwner: String
    var repoName: String
    var summaryText: String
    var detailTitle: String?
    var targetIssueNumber: Int?
    var commitSHA: String?
    var branchName: String?
    var releaseTag: String?
    var createdAt = ""

    var repoRef: RepoRef { RepoRef(owner: repoOwner, name: repoName) }
}
