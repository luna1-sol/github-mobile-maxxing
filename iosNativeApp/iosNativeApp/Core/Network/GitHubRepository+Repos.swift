import Foundation

extension GitHubRepository {
    // MARK: Lists

    func viewerRepositories() async throws -> [RepoSummary] {
        let data = try await client.graphQL("""
            query {
              viewer {
                repositories(first: 50, orderBy: { field: UPDATED_AT, direction: DESC }, ownerAffiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER]) {
                  nodes { \(Self.repoFields) }
                }
              }
            }
            """)
        return (data["viewer"]?["repositories"]?["nodes"]?.items ?? []).map(Self.parseRepo)
    }

    func starredRepositories() async throws -> [RepoSummary] {
        let data = try await client.graphQL("""
            query {
              viewer {
                starredRepositories(first: 50, orderBy: { field: STARRED_AT, direction: DESC }) {
                  nodes { \(Self.repoFields) }
                }
              }
            }
            """)
        return (data["viewer"]?["starredRepositories"]?["nodes"]?.items ?? []).map(Self.parseRepo)
    }

    func searchRepositories(_ query: String) async throws -> [RepoSummary] {
        let data = try await client.graphQL("""
            query($q: String!) {
              search(query: $q, type: REPOSITORY, first: 30) {
                nodes { ... on Repository { \(Self.repoFields) } }
              }
            }
            """, variables: ["q": .string(query)])
        return (data["search"]?["nodes"]?.items ?? []).compactMap { node in
            guard node["nameWithOwner"]?.string?.isEmpty == false else { return nil }
            return Self.parseRepo(node)
        }
    }

    func userRepositories(_ login: String, isOrganization: Bool) async throws -> [RepoSummary] {
        let base = isOrganization ? "orgs" : "users"
        let json = try await client.json(
            .get, "\(base)/\(APIPath.seg(login))/repos",
            query: ["per_page": "50", "sort": isOrganization ? "updated" : "pushed", "type": isOrganization ? "public" : "owner"],
            failure: String(localized: "Failed to load repositories"))
        return json.items.map(Self.parseRestRepo)
    }

    // MARK: Detail

    func repoDetail(_ repo: RepoRef) async throws -> RepoDetail {
        let data = try await client.graphQL("""
            query($owner: String!, $name: String!) {
              repository(owner: $owner, name: $name) {
                \(Self.repoFields)
                homepageUrl
                licenseInfo { name }
                watchers { totalCount }
                repositoryTopics(first: 10) { nodes { topic { name } } }
                parent { name nameWithOwner owner { login avatarUrl } defaultBranchRef { name } }
              }
            }
            """, variables: ["owner": .string(repo.owner), "name": .string(repo.name)])
        guard let node = data["repository"] else {
            throw GitHubAPIError(statusCode: 404, message: String(localized: "Repository \(repo.fullName) not found"), isSynthetic: true)
        }
        return RepoDetail(
            summary: Self.parseRepo(node),
            homepageURL: node["homepageUrl"]?.string.flatMap { $0.isEmpty ? nil : $0 },
            licenseName: node["licenseInfo"]?["name"]?.string,
            topics: (node["repositoryTopics"]?["nodes"]?.items ?? []).compactMap { $0["topic"]?["name"]?.string },
            watchersCount: node["watchers"]?["totalCount"]?.int ?? 0
        )
    }

    func branches(_ repo: RepoRef) async throws -> [BranchRef] {
        let json = try await client.json(.get, "\(APIPath.repo(repo.owner, repo.name))/branches", query: ["per_page": "100"],
                                         noCache: true, failure: String(localized: "Failed to load branches"))
        return json.items.compactMap { obj in
            guard let name = obj["name"]?.string else { return nil }
            return BranchRef(name: name, sha: obj["commit"]?["sha"]?.string ?? "")
        }
    }

    func directory(_ repo: RepoRef, path: String, ref: String?) async throws -> [TreeEntry] {
        let sub = APIPath.subPath(path)
        let url = "\(APIPath.repo(repo.owner, repo.name))/contents" + (sub.isEmpty ? "" : "/\(sub)")
        var query: [String: String] = [:]
        if let ref, !ref.isEmpty { query["ref"] = ref }
        let json = try await client.json(.get, url, query: query, noCache: true, failure: String(localized: "Failed to list directory"))
        return json.items
            .map { item in
                TreeEntry(
                    path: item["path"]?.string ?? "",
                    name: item["name"]?.string ?? "",
                    type: item["type"]?.string == "dir" ? .tree : .blob,
                    sha: item["sha"]?.string ?? "",
                    size: item["size"]?.int64 ?? 0
                )
            }
            .sorted { a, b in
                if a.type != b.type { return a.type == .tree }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }

    func file(_ repo: RepoRef, path: String, ref: String?) async throws -> FileContent {
        var query: [String: String] = [:]
        if let ref, !ref.isEmpty { query["ref"] = ref }
        let json = try await client.json(.get, "\(APIPath.repo(repo.owner, repo.name))/contents/\(APIPath.subPath(path))",
                                         query: query, noCache: true, failure: String(localized: "Failed to fetch file"))
        var content = FileContent(
            path: json["path"]?.string ?? path,
            name: json["name"]?.string ?? (path as NSString).lastPathComponent,
            size: json["size"]?.int64 ?? 0,
            content: "",
            htmlURL: json["html_url"]?.string ?? "",
            sha: json["sha"]?.string ?? ""
        )
        guard let raw = json["content"]?.string else { return content }
        if json["encoding"]?.string == "base64" {
            let bytes = Data(base64Encoded: raw, options: .ignoreUnknownCharacters) ?? Data()
            if bytes.prefix(512).contains(0) || String(data: bytes, encoding: .utf8) == nil {
                content.isBinary = true
            } else {
                content.content = String(decoding: bytes, as: UTF8.self)
            }
        } else {
            content.content = raw
        }
        return content
    }

    /// README as raw Markdown, or nil when the repository has none.
    func readme(_ repo: RepoRef, ref: String?) async throws -> String? {
        var query: [String: String] = [:]
        if let ref, !ref.isEmpty { query["ref"] = ref }
        let (data, response) = try await client.send(.get, "\(APIPath.repo(repo.owner, repo.name))/readme", query: query,
                                                     accept: "application/vnd.github.raw+json")
        if response.statusCode == 404 { return nil }
        try GitHubHttpClient.ensureSuccess(response, data: data, failure: String(localized: "Failed to load README"))
        return String(decoding: data, as: UTF8.self)
    }

    func commits(_ repo: RepoRef, ref: String?, path: String = "") async throws -> [CommitSummary] {
        var query = ["per_page": "40"]
        if let ref, !ref.isEmpty { query["sha"] = ref }
        if !path.isEmpty { query["path"] = path }
        let json = try await client.json(.get, "\(APIPath.repo(repo.owner, repo.name))/commits", query: query,
                                         failure: String(localized: "Failed to load commits"))
        return json.items.map(Self.parseCommit)
    }

    func commitDetail(_ repo: RepoRef, sha: String) async throws -> CommitDetail {
        let json = try await client.json(.get, "\(APIPath.repo(repo.owner, repo.name))/commits/\(APIPath.seg(sha))",
                                         failure: String(localized: "Failed to load commit"))
        return CommitDetail(
            summary: Self.parseCommit(json),
            additions: json["stats"]?["additions"]?.int ?? 0,
            deletions: json["stats"]?["deletions"]?.int ?? 0,
            files: (json["files"]?.items ?? []).map(Self.parseFileChange),
            htmlURL: json["html_url"]?.string ?? ""
        )
    }

    static func parseCommit(_ obj: JSONValue) -> CommitSummary {
        let sha = obj["sha"]?.string ?? ""
        let message = obj["commit"]?["message"]?.string ?? ""
        let lines = message.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        return CommitSummary(
            sha: sha,
            shortSHA: String(sha.prefix(7)),
            headline: lines.first.map(String.init) ?? "",
            body: lines.count > 1 ? String(lines[1]).trimmingCharacters(in: .whitespacesAndNewlines) : "",
            authorName: obj["commit"]?["author"]?["name"]?.string ?? obj["author"]?["login"]?.string ?? "",
            authorLogin: obj["author"]?["login"]?.string,
            authorAvatarURL: obj["author"]?["avatar_url"]?.string ?? "",
            committedAt: obj["commit"]?["committer"]?["date"]?.string ?? obj["commit"]?["author"]?["date"]?.string ?? "",
            isVerified: obj["commit"]?["verification"]?["verified"]?.bool ?? false
        )
    }

    // MARK: Mutations

    func setStarred(_ repo: RepoRef, starred: Bool) async throws {
        try await client.expectSuccess(starred ? .put : .delete, "user/starred/\(APIPath.seg(repo.owner))/\(APIPath.seg(repo.name))",
                                       failure: String(localized: "Failed to update star"))
    }

    func isWatching(_ repo: RepoRef) async throws -> Bool {
        let (_, response) = try await client.send(.get, "\(APIPath.repo(repo.owner, repo.name))/subscription")
        return response.statusCode == 200
    }

    func setWatching(_ repo: RepoRef, watching: Bool) async throws {
        if watching {
            try await client.expectSuccess(.put, "\(APIPath.repo(repo.owner, repo.name))/subscription",
                                           body: ["subscribed": true], failure: String(localized: "Failed to watch repository"))
        } else {
            try await client.expectSuccess(.delete, "\(APIPath.repo(repo.owner, repo.name))/subscription",
                                           failure: String(localized: "Failed to unwatch repository"))
        }
    }
}
