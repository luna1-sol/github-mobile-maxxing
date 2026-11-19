import Foundation

extension GitHubRepository {
    func searchIssuesAndPulls(_ query: String) async throws -> [IssueOrPullSummary] {
        try await searchIssuesGraphQL("\(query) sort:updated-desc", first: 30)
    }

    func searchCode(_ query: String) async throws -> [CodeSearchHit] {
        let (data, response) = try await client.send(.get, "search/code", query: ["q": query, "per_page": "30"],
                                                     accept: "application/vnd.github.text-match+json")
        try GitHubHttpClient.ensureSuccess(response, data: data, failure: String(localized: "Code search failed"))
        return (try JSONValue.parse(data))["items"]?.items.map { item in
            let repo = item["repository"]
            let full = repo?["full_name"]?.string ?? ""
            let parts = full.split(separator: "/", maxSplits: 1).map(String.init)
            return CodeSearchHit(
                name: item["name"]?.string ?? "",
                path: item["path"]?.string ?? "",
                sha: item["sha"]?.string ?? "",
                repoFullName: full,
                repoOwner: repo?["owner"]?["login"]?.string ?? parts.first ?? "",
                repoName: repo?["name"]?.string ?? (parts.count > 1 ? parts[1] : ""),
                htmlURL: item["html_url"]?.string ?? "",
                fragments: (item["text_matches"]?.items ?? []).compactMap { $0["fragment"]?.string.flatMap { $0.isEmpty ? nil : $0 } }
            )
        } ?? []
    }

    func searchUsers(_ query: String) async throws -> [UserSummary] {
        let json = try await client.json(.get, "search/users", query: ["q": query, "per_page": "30"], failure: String(localized: "User search failed"))
        return (json["items"]?.items ?? []).map { Self.parseUser($0) }
    }
}
