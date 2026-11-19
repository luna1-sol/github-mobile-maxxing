import Foundation

// Port of core/model/src/commonMain/kotlin/dev/maxxing/github/model/NotificationModels.kt

enum NotificationSubjectType: String, Hashable, Sendable {
    case issue, pullRequest, commit, release, discussion, checkSuite, unknown

    init(raw: String) {
        switch raw {
        case "Issue": self = .issue
        case "PullRequest": self = .pullRequest
        case "Commit": self = .commit
        case "Release": self = .release
        case "Discussion": self = .discussion
        case "CheckSuite": self = .checkSuite
        default: self = .unknown
        }
    }
}

enum NotificationReason: String, Hashable, Sendable {
    case assign, author, comment, ciActivity = "ci_activity", invitation, manual, mention
    case reviewRequested = "review_requested", securityAlert = "security_alert"
    case stateChange = "state_change", subscribed, teamMention = "team_mention", other

    init(raw: String) { self = NotificationReason(rawValue: raw) ?? .other }

    /// Reasons that usually need the viewer's attention.
    var isUrgent: Bool { [.mention, .teamMention, .reviewRequested, .assign, .securityAlert].contains(self) }
}

struct NotificationThread: Hashable, Sendable, Identifiable {
    var id: String
    var unread: Bool
    var reason: NotificationReason
    var updatedAt: String
    var subjectTitle: String
    var subjectType: NotificationSubjectType
    var subjectURL: String?
    var latestCommentURL: String?
    var repoFullName: String
    var repoOwner: String
    var repoName: String
    var repoOwnerAvatarURL = ""
    var isPrivate = false

    private var lastURLSegment: String? {
        guard let subjectURL, let last = subjectURL.split(separator: "/").last else { return nil }
        return String(last)
    }

    var subjectNumber: Int? {
        guard subjectType == .issue || subjectType == .pullRequest else { return nil }
        return lastURLSegment.flatMap(Int.init)
    }

    var issueRef: IssueRef? {
        subjectNumber.map { IssueRef(owner: repoOwner, repo: repoName, number: $0) }
    }

    var htmlFallbackURL: URL {
        let base = "https://github.com/\(repoFullName)"
        let s: String
        switch subjectType {
        case .issue: s = subjectNumber.map { "\(base)/issues/\($0)" } ?? "\(base)/issues"
        case .pullRequest: s = subjectNumber.map { "\(base)/pull/\($0)" } ?? "\(base)/pulls"
        case .checkSuite: s = "\(base)/actions"
        case .commit: s = lastURLSegment.map { "\(base)/commit/\($0)" } ?? "\(base)/commits"
        case .release: s = "\(base)/releases"
        case .discussion: s = "\(base)/discussions"
        case .unknown: s = base
        }
        return URL(string: s) ?? URL(string: "https://github.com")!
    }
}

enum InboxFilter: String, CaseIterable, Hashable, Sendable {
    case unread, participating, all
}
