import Foundation

/// Feature-level API (port of `GitHubRepository` + `GitHubGraphQlService` + `GitHubRestService`).
/// Split across `GitHubRepository+*.swift` files by area.
final class GitHubRepository {
    let client: GitHubHttpClient

    init(client: GitHubHttpClient) {
        self.client = client
    }

    // MARK: Shared parsers

    static let repoFields = """
        id
        name
        nameWithOwner
        description
        isPrivate
        isFork
        isArchived
        hasIssuesEnabled
        viewerPermission
        stargazerCount
        forkCount
        updatedAt
        viewerHasStarred
        owner { login avatarUrl }
        primaryLanguage { name color }
        defaultBranchRef { name }
        issues(states: OPEN) { totalCount }
        pullRequests(states: OPEN) { totalCount }
        """

    static func parseUser(_ obj: JSONValue?) -> UserSummary {
        UserSummary(
            login: obj?["login"]?.string ?? "ghost",
            avatarURL: obj?["avatarUrl"]?.string ?? obj?["avatar_url"]?.string ?? "",
            htmlURL: obj?["url"]?.string ?? obj?["html_url"]?.string ?? ""
        )
    }

    static func parseLabels(_ nodes: JSONValue?) -> [LabelTag] {
        (nodes?.items ?? []).compactMap { node in
            guard let name = node["name"]?.string else { return nil }
            return LabelTag(name: name, colorHex: node["color"]?.string ?? "6750A4", description: node["description"]?.string)
        }
    }

    static func parseReactionGroups(_ groups: JSONValue?) -> [ReactionSummary] {
        (groups?.items ?? []).compactMap { group in
            guard let content = group["content"]?.string else { return nil }
            let count = group["reactors"]?["totalCount"]?.int ?? 0
            let reacted = group["viewerHasReacted"]?.bool ?? false
            guard count > 0 || reacted else { return nil }
            return ReactionSummary(content: content, count: count, viewerHasReacted: reacted)
        }
    }

    /// GraphQL `Repository` node -> `RepoSummary`.
    static func parseRepo(_ obj: JSONValue) -> RepoSummary {
        let owner = obj["owner"]
        let parent: RepoParentSummary? = obj["parent"].flatMap { p in
            guard let full = p["nameWithOwner"]?.string, !full.isEmpty else { return nil }
            let parts = full.split(separator: "/", maxSplits: 1).map(String.init)
            return RepoParentSummary(
                name: p["name"]?.string ?? parts.last ?? full,
                owner: p["owner"]?["login"]?.string ?? parts.first ?? "",
                fullName: full,
                defaultBranch: p["defaultBranchRef"]?["name"]?.string ?? "main",
                ownerAvatarURL: p["owner"]?["avatarUrl"]?.string ?? ""
            )
        }
        return RepoSummary(
            id: obj["id"]?.string ?? "",
            name: obj["name"]?.string ?? "",
            owner: owner?["login"]?.string ?? "",
            fullName: obj["nameWithOwner"]?.string ?? "",
            description: obj["description"]?.string,
            language: obj["primaryLanguage"]?["name"]?.string,
            languageColorHex: obj["primaryLanguage"]?["color"]?.string,
            stargazersCount: obj["stargazerCount"]?.int ?? 0,
            forksCount: obj["forkCount"]?.int ?? 0,
            openIssuesCount: obj["issues"]?["totalCount"]?.int ?? 0,
            openPullRequestsCount: obj["pullRequests"]?["totalCount"]?.int,
            isPrivate: obj["isPrivate"]?.bool ?? false,
            isFork: obj["isFork"]?.bool ?? false,
            defaultBranch: obj["defaultBranchRef"]?["name"]?.string ?? "main",
            updatedAt: obj["updatedAt"]?.string ?? "",
            ownerAvatarURL: owner?["avatarUrl"]?.string ?? "",
            viewerHasStarred: obj["viewerHasStarred"]?.bool ?? false,
            viewerPermission: obj["viewerPermission"]?.string?.uppercased(),
            hasKnownPermission: obj.has("viewerPermission"),
            isArchived: obj["isArchived"]?.bool ?? false,
            hasIssuesEnabled: obj["hasIssuesEnabled"]?.bool ?? true,
            parent: parent
        )
    }

    /// REST repository JSON -> `RepoSummary`.
    static func parseRestRepo(_ obj: JSONValue) -> RepoSummary {
        let full = obj["full_name"]?.string ?? ""
        let perms = obj["permissions"]
        let permission: String? = perms.flatMap { p in
            if p["admin"]?.bool == true { return "ADMIN" }
            if p["maintain"]?.bool == true { return "MAINTAIN" }
            if p["push"]?.bool == true { return "WRITE" }
            if p["triage"]?.bool == true { return "TRIAGE" }
            if p["pull"]?.bool == true { return "READ" }
            return nil
        }
        return RepoSummary(
            id: obj["node_id"]?.string ?? obj["id"]?.string ?? full,
            name: obj["name"]?.string ?? "",
            owner: obj["owner"]?["login"]?.string ?? String(full.split(separator: "/").first ?? ""),
            fullName: full,
            description: obj["description"]?.string,
            language: obj["language"]?.string,
            languageColorHex: nil,
            stargazersCount: obj["stargazers_count"]?.int ?? 0,
            forksCount: obj["forks_count"]?.int ?? 0,
            openIssuesCount: obj["open_issues_count"]?.int ?? 0,
            isPrivate: obj["private"]?.bool ?? false,
            isFork: obj["fork"]?.bool ?? false,
            defaultBranch: obj["default_branch"]?.string ?? "main",
            updatedAt: obj["updated_at"]?.string ?? obj["pushed_at"]?.string ?? "",
            ownerAvatarURL: obj["owner"]?["avatar_url"]?.string ?? "",
            viewerPermission: permission,
            hasKnownPermission: permission != nil,
            isArchived: obj["archived"]?.bool ?? false,
            hasIssuesEnabled: obj["has_issues"]?.bool ?? true
        )
    }

    static func checkRollupState(_ obj: JSONValue) -> CheckRollupSummary? {
        obj["commits"]?["nodes"]?[0]?["commit"]?["statusCheckRollup"]?["state"]?.string.map { CheckRollupSummary(state: $0) }
    }
}
