import Foundation

// Port of core/model/src/commonMain/kotlin/dev/maxxing/github/model/IssuePullModels.kt

enum IssueOrPullKind: String, Hashable, Codable, Sendable {
    case issue = "ISSUE"
    case pullRequest = "PULL_REQUEST"
}

enum IssueOrPullState: String, Hashable, Sendable {
    case open = "OPEN"
    case closed = "CLOSED"
    case merged = "MERGED"

    init(raw: String?) {
        switch raw?.uppercased() {
        case "MERGED": self = .merged
        case "CLOSED": self = .closed
        default: self = .open
        }
    }
}

enum IssueStateFilter: String, CaseIterable, Hashable, Sendable {
    case open, closed, all
}

enum IssueFilterPreset: String, CaseIterable, Hashable, Sendable {
    case created, assigned, reviewRequested, mentioned
}

enum MergeMethod: String, CaseIterable, Hashable, Sendable {
    case squash, merge, rebase
}

enum ReviewEvent: String, CaseIterable, Hashable, Sendable {
    case approve = "APPROVE"
    case requestChanges = "REQUEST_CHANGES"
    case comment = "COMMENT"
}

struct LabelTag: Hashable, Sendable, Identifiable {
    var name: String
    var colorHex: String
    var description: String?
    var id: String { name }
}

struct MilestoneSummary: Hashable, Sendable {
    var number: Int
    var title: String
    var description: String?
    var state = "open"
    var dueOn: String?
}

struct CheckRollupSummary: Hashable, Sendable {
    /// SUCCESS, FAILURE, PENDING, EXPECTED, ERROR
    var state: String
}

/// Navigation target for an issue or pull request.
struct IssueRef: Hashable, Codable, Sendable {
    var owner: String
    var repo: String
    var number: Int
    var repoRef: RepoRef { RepoRef(owner: owner, name: repo) }
    var webURL: URL { URL(string: "https://github.com/\(owner)/\(repo)/issues/\(number)")! }
}

struct IssueOrPullSummary: Hashable, Sendable, Identifiable {
    var id: String
    var number: Int
    var title: String
    var kind: IssueOrPullKind
    var state: IssueOrPullState
    var isDraft = false
    var repoFullName: String
    var repoOwner: String
    var repoName: String
    var author: UserSummary
    var createdAt: String
    var updatedAt: String
    var commentCount = 0
    var labels: [LabelTag] = []
    var checkRollup: CheckRollupSummary?
    var reviewDecision: String?

    var ref: IssueRef { IssueRef(owner: repoOwner, repo: repoName, number: number) }
}

struct ReactionSummary: Hashable, Sendable, Identifiable {
    /// THUMBS_UP, THUMBS_DOWN, LAUGH, HOORAY, CONFUSED, HEART, ROCKET, EYES
    var content: String
    var count: Int
    var viewerHasReacted: Bool
    var id: String { content }
}

enum ReactionContent: String, CaseIterable, Sendable {
    case thumbsUp = "THUMBS_UP", thumbsDown = "THUMBS_DOWN", laugh = "LAUGH", hooray = "HOORAY"
    case confused = "CONFUSED", heart = "HEART", rocket = "ROCKET", eyes = "EYES"

    var emoji: String {
        switch self {
        case .thumbsUp: "👍"
        case .thumbsDown: "👎"
        case .laugh: "😄"
        case .hooray: "🎉"
        case .confused: "😕"
        case .heart: "❤️"
        case .rocket: "🚀"
        case .eyes: "👀"
        }
    }
}

enum TimelineEvent: Hashable, Sendable, Identifiable {
    case comment(CommentEvent)
    case review(ReviewItem)
    case commit(CommitItem)
    case stateChange(StateChange)

    struct CommentEvent: Hashable, Sendable {
        var id: String
        var createdAt: String
        var author: UserSummary
        var body: String
        var authorAssociation: String?
        var reactions: [ReactionSummary] = []
        var viewerCanUpdate = false
        var viewerCanDelete = false
    }

    struct ReviewItem: Hashable, Sendable {
        var id: String
        var createdAt: String
        var author: UserSummary
        /// APPROVED, CHANGES_REQUESTED, COMMENTED, DISMISSED
        var state: String
        var body: String
    }

    struct CommitItem: Hashable, Sendable {
        var id: String
        var createdAt: String
        var oidShort: String
        var messageHeadline: String
        var authorName: String
    }

    enum StateAction: Hashable, Sendable {
        case closed, reopened
        case merged(into: String)
    }

    struct StateChange: Hashable, Sendable {
        var id: String
        var createdAt: String
        var actor: UserSummary?
        var action: StateAction
    }

    var id: String {
        switch self {
        case .comment(let e): e.id
        case .review(let e): e.id
        case .commit(let e): e.id
        case .stateChange(let e): e.id
        }
    }
}

struct IssueOrPullDetail: Hashable, Sendable {
    var id: String
    var number: Int
    var title: String
    var body: String
    var kind: IssueOrPullKind
    var state: IssueOrPullState
    var isDraft = false
    var repoOwner: String
    var repoName: String
    var author: UserSummary
    var createdAt: String
    var updatedAt: String
    var labels: [LabelTag] = []
    var assignees: [UserSummary] = []
    var milestone: MilestoneSummary?
    var headRefName: String?
    var baseRefName: String?
    var additions = 0
    var deletions = 0
    var changedFilesCount = 0
    /// MERGEABLE, CONFLICTING, UNKNOWN
    var mergeable: String?
    /// CLEAN, BLOCKED, BEHIND, DIRTY, DRAFT, HAS_HOOKS, UNKNOWN, UNSTABLE
    var mergeStateStatus: String?
    var reviewDecision: String?
    var checkRollup: CheckRollupSummary?
    var htmlURL = ""
    var timeline: [TimelineEvent] = []
    var viewerPermission: String?
    var viewerCanUpdate = false
    var viewerCanCloseOrReopen = false
    var viewerCanMerge = false
    var viewerCanEditMetadata = false
    var headRefOid: String?
    var reactions: [ReactionSummary] = []
    var requestedReviewers: [UserSummary] = []

    var repoFullName: String { "\(repoOwner)/\(repoName)" }
    var isPullRequest: Bool { kind == .pullRequest }
}

enum FileChangeStatus: String, Hashable, Sendable {
    case added, modified, removed, renamed, copied, changed

    init(raw: String) {
        self = FileChangeStatus(rawValue: raw.lowercased()) ?? .modified
    }
}

enum DiffLineKind: Hashable, Sendable { case context, added, removed, meta }

struct DiffLine: Hashable, Sendable {
    var kind: DiffLineKind
    var content: String
    var oldLineNumber: Int?
    var newLineNumber: Int?
}

struct DiffHunk: Hashable, Sendable {
    var header: String
    var oldStart: Int
    var oldCount: Int
    var newStart: Int
    var newCount: Int
    var lines: [DiffLine]
}

struct PullFileChange: Hashable, Sendable, Identifiable {
    var filename: String
    var previousFilename: String?
    var status: FileChangeStatus
    var additions: Int
    var deletions: Int
    var patch: String?
    var hunks: [DiffHunk] = []
    var id: String { filename }
}
