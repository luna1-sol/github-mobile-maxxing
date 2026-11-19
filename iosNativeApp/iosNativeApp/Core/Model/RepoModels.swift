import Foundation

// Port of core/model/src/commonMain/kotlin/dev/maxxing/github/model/RepoModels.kt

/// Lightweight identity of a repository used for navigation.
struct RepoRef: Hashable, Codable, Sendable {
    var owner: String
    var name: String
    var fullName: String { "\(owner)/\(name)" }
    var webURL: URL { URL(string: "https://github.com/\(owner)/\(name)") ?? URL(string: "https://github.com")! }
}

struct RepoParentSummary: Hashable, Sendable {
    var name: String
    var owner: String
    var fullName: String
    var defaultBranch = "main"
    var ownerAvatarURL = ""
}

struct RepoSummary: Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var owner: String
    var fullName: String
    var description: String?
    var language: String?
    var languageColorHex: String?
    var stargazersCount = 0
    var forksCount = 0
    var openIssuesCount = 0
    var openPullRequestsCount: Int?
    var isPrivate = false
    var isFork = false
    var defaultBranch = "main"
    var updatedAt = ""
    var ownerAvatarURL = ""
    var viewerHasStarred = false
    var viewerPermission: String?
    var hasKnownPermission = false
    var isArchived = false
    var hasIssuesEnabled = true
    var parent: RepoParentSummary?

    var ref: RepoRef { RepoRef(owner: owner, name: name) }
}

struct RepoCapabilities: Equatable, Sendable {
    var viewerPermission: String?
    var permissionResolved: Bool
    var isArchived: Bool
    var canPush: Bool
    var canTriage: Bool
    var canCreateIssue: Bool
    var canComment: Bool

    private static let writePerms: Set<String> = ["ADMIN", "MAINTAIN", "WRITE"]
    private static let triagePerms: Set<String> = ["ADMIN", "MAINTAIN", "WRITE", "TRIAGE"]

    /// Port of `resolveRepoCapabilities`.
    static func resolve(_ summary: RepoSummary, viewerLogin: String?) -> RepoCapabilities {
        let perm = summary.viewerPermission?.uppercased()
        let resolved = summary.hasKnownPermission || perm != nil
        let hasWrite: Bool
        if resolved {
            hasWrite = perm.map { writePerms.contains($0) } ?? false
        } else {
            hasWrite = !(viewerLogin ?? "").isEmpty && viewerLogin!.caseInsensitiveCompare(summary.owner) == .orderedSame
        }
        let hasTriage = resolved ? (perm.map { triagePerms.contains($0) } ?? false) : hasWrite
        return RepoCapabilities(
            viewerPermission: perm,
            permissionResolved: resolved,
            isArchived: summary.isArchived,
            canPush: !summary.isArchived && hasWrite,
            canTriage: !summary.isArchived && hasTriage,
            canCreateIssue: !summary.isArchived && summary.hasIssuesEnabled,
            canComment: !summary.isArchived
        )
    }
}

struct RepoDetail: Hashable, Sendable {
    var summary: RepoSummary
    var homepageURL: String?
    var licenseName: String?
    var topics: [String] = []
    var watchersCount = 0
}

struct BranchRef: Hashable, Sendable, Identifiable {
    var name: String
    var sha: String
    var id: String { name }
}

enum TreeEntryType: String, Sendable { case tree, blob }

struct TreeEntry: Hashable, Sendable, Identifiable {
    var path: String
    var name: String
    var type: TreeEntryType
    var sha: String
    var size: Int64 = 0
    var id: String { path }
}

struct FileContent: Hashable, Sendable {
    var path: String
    var name: String
    var size: Int64
    var content: String
    var isBinary = false
    var htmlURL = ""
    var sha = ""
}

struct CommitSummary: Hashable, Sendable, Identifiable {
    var sha: String
    var shortSHA: String
    var headline: String
    var body = ""
    var authorName: String
    var authorLogin: String?
    var authorAvatarURL = ""
    var committedAt = ""
    var isVerified = false
    var id: String { sha }
}

struct CommitDetail: Hashable, Sendable {
    var summary: CommitSummary
    var additions = 0
    var deletions = 0
    var files: [PullFileChange] = []
    var htmlURL = ""
}
