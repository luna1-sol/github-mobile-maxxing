import Foundation

extension GitHubRepository {
    private static let triageOrHigher: Set<String> = ["ADMIN", "MAINTAIN", "WRITE", "TRIAGE"]
    private static let writeOrHigher: Set<String> = ["ADMIN", "MAINTAIN", "WRITE"]

    // MARK: Lists

    func myIssuesAndPulls(preset: IssueFilterPreset, viewerLogin: String, state: IssueStateFilter) async throws -> [IssueOrPullSummary] {
        let qualifier = switch preset {
        case .created: "author:\(viewerLogin)"
        case .assigned: "assignee:\(viewerLogin)"
        case .reviewRequested: "is:pr review-requested:\(viewerLogin)"
        case .mentioned: "mentions:\(viewerLogin)"
        }
        let stateQualifier = switch state {
        case .open: "is:open "
        case .closed: "is:closed "
        case .all: ""
        }
        return try await searchIssuesGraphQL("\(stateQualifier)\(qualifier) sort:updated-desc")
    }

    /// GraphQL issue search; also backs the global "Issues & PRs" search.
    func searchIssuesGraphQL(_ query: String, first: Int = 35) async throws -> [IssueOrPullSummary] {
        let data = try await client.graphQL("""
            query($q: String!) {
              search(query: $q, type: ISSUE, first: \(first)) {
                nodes {
                  __typename
                  ... on Issue {
                    id number title state createdAt updatedAt
                    author { login avatarUrl url }
                    repository { nameWithOwner name owner { login } }
                    comments { totalCount }
                    labels(first: 6) { nodes { name color description } }
                  }
                  ... on PullRequest {
                    id number title state isDraft createdAt updatedAt reviewDecision
                    author { login avatarUrl url }
                    repository { nameWithOwner name owner { login } }
                    comments { totalCount }
                    labels(first: 6) { nodes { name color description } }
                    commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
                  }
                }
              }
            }
            """, variables: ["q": .string(query)])
        return (data["search"]?["nodes"]?.items ?? []).compactMap { node in
            guard let type = node["__typename"]?.string, type == "Issue" || type == "PullRequest",
                  let repo = node["repository"] else { return nil }
            return IssueOrPullSummary(
                id: node["id"]?.string ?? "",
                number: node["number"]?.int ?? 0,
                title: node["title"]?.string ?? "",
                kind: type == "PullRequest" ? .pullRequest : .issue,
                state: IssueOrPullState(raw: node["state"]?.string),
                isDraft: node["isDraft"]?.bool ?? false,
                repoFullName: repo["nameWithOwner"]?.string ?? "",
                repoOwner: repo["owner"]?["login"]?.string ?? "",
                repoName: repo["name"]?.string ?? "",
                author: Self.parseUser(node["author"]),
                createdAt: node["createdAt"]?.string ?? "",
                updatedAt: node["updatedAt"]?.string ?? "",
                commentCount: node["comments"]?["totalCount"]?.int ?? 0,
                labels: Self.parseLabels(node["labels"]?["nodes"]),
                checkRollup: Self.checkRollupState(node),
                reviewDecision: node["reviewDecision"]?.string
            )
        }
    }

    func repoIssuesOrPulls(_ repo: RepoRef, pullRequests: Bool, state: IssueStateFilter) async throws -> [IssueOrPullSummary] {
        let field = pullRequests ? "pullRequests" : "issues"
        let states = switch state {
        case .open: "[OPEN]"
        case .closed: pullRequests ? "[CLOSED, MERGED]" : "[CLOSED]"
        case .all: pullRequests ? "[OPEN, CLOSED, MERGED]" : "[OPEN, CLOSED]"
        }
        let data = try await client.graphQL("""
            query($owner: String!, $name: String!) {
              repository(owner: $owner, name: $name) {
                \(field)(first: 30, states: \(states), orderBy: { field: UPDATED_AT, direction: DESC }) {
                  nodes {
                    id number title state \(pullRequests ? "isDraft reviewDecision" : "")
                    createdAt updatedAt
                    author { login avatarUrl url }
                    comments { totalCount }
                    labels(first: 6) { nodes { name color description } }
                    \(pullRequests ? "commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }" : "")
                  }
                }
              }
            }
            """, variables: ["owner": .string(repo.owner), "name": .string(repo.name)])
        return (data["repository"]?[field]?["nodes"]?.items ?? []).map { node in
            IssueOrPullSummary(
                id: node["id"]?.string ?? "",
                number: node["number"]?.int ?? 0,
                title: node["title"]?.string ?? "",
                kind: pullRequests ? .pullRequest : .issue,
                state: IssueOrPullState(raw: node["state"]?.string),
                isDraft: node["isDraft"]?.bool ?? false,
                repoFullName: repo.fullName,
                repoOwner: repo.owner,
                repoName: repo.name,
                author: Self.parseUser(node["author"]),
                createdAt: node["createdAt"]?.string ?? "",
                updatedAt: node["updatedAt"]?.string ?? "",
                commentCount: node["comments"]?["totalCount"]?.int ?? 0,
                labels: Self.parseLabels(node["labels"]?["nodes"]),
                checkRollup: Self.checkRollupState(node),
                reviewDecision: node["reviewDecision"]?.string
            )
        }
    }

    // MARK: Detail

    func issueOrPullDetail(_ ref: IssueRef) async throws -> IssueOrPullDetail {
        let user = "{ login avatarUrl url }"
        let comment = """
            ... on IssueComment {
              id createdAt body authorAssociation viewerCanUpdate viewerCanDelete
              author \(user)
              reactionGroups { content viewerHasReacted reactors { totalCount } }
            }
            ... on ClosedEvent { id createdAt actor \(user) }
            ... on ReopenedEvent { id createdAt actor \(user) }
            """
        let common = """
            id number title body state url viewerCanUpdate createdAt updatedAt
            author \(user)
            labels(first: 10) { nodes { name color description } }
            assignees(first: 6) { nodes \(user) }
            milestone { number title description state dueOn }
            reactionGroups { content viewerHasReacted reactors { totalCount } }
            """
        let data = try await client.graphQL("""
            query($owner: String!, $name: String!, $number: Int!) {
              repository(owner: $owner, name: $name) {
                viewerPermission
                issueOrPullRequest(number: $number) {
                  __typename
                  ... on Issue {
                    \(common)
                    timelineItems(first: 50, itemTypes: [ISSUE_COMMENT, CLOSED_EVENT, REOPENED_EVENT]) {
                      nodes { __typename \(comment) }
                    }
                  }
                  ... on PullRequest {
                    \(common)
                    isDraft headRefName headRefOid baseRefName additions deletions changedFiles
                    mergeable mergeStateStatus reviewDecision
                    reviewRequests(first: 10) { nodes { requestedReviewer { ... on User \(user) } } }
                    commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
                    timelineItems(first: 60, itemTypes: [ISSUE_COMMENT, PULL_REQUEST_REVIEW, PULL_REQUEST_COMMIT, MERGED_EVENT, CLOSED_EVENT, REOPENED_EVENT]) {
                      nodes {
                        __typename
                        \(comment)
                        ... on PullRequestReview { id createdAt state body author \(user) }
                        ... on PullRequestCommit { id commit { abbreviatedOid messageHeadline committedDate author { name } } }
                        ... on MergedEvent { id createdAt actor \(user) mergeRefName }
                      }
                    }
                  }
                }
              }
            }
            """, variables: ["owner": .string(ref.owner), "name": .string(ref.repo), "number": .number(Double(ref.number))])

        let repoNode = data["repository"]
        let permission = repoNode?["viewerPermission"]?.string?.uppercased()
        guard let item = repoNode?["issueOrPullRequest"] else {
            throw GitHubAPIError(statusCode: 404, message: "#\(ref.number) not found in \(ref.owner)/\(ref.repo)", isSynthetic: true)
        }
        let isPR = item["__typename"]?.string == "PullRequest"
        let canUpdate = item["viewerCanUpdate"]?.bool ?? false
        let canTriage = permission.map { Self.triageOrHigher.contains($0) } ?? false
        let canWrite = permission.map { Self.writeOrHigher.contains($0) } ?? false

        let timeline: [TimelineEvent] = (item["timelineItems"]?["nodes"]?.items ?? []).compactMap { node in
            let id = node["id"]?.string ?? UUID().uuidString
            let createdAt = node["createdAt"]?.string ?? ""
            switch node["__typename"]?.string {
            case "IssueComment":
                return .comment(.init(
                    id: id, createdAt: createdAt,
                    author: Self.parseUser(node["author"]),
                    body: node["body"]?.string ?? "",
                    authorAssociation: node["authorAssociation"]?.string,
                    reactions: Self.parseReactionGroups(node["reactionGroups"]),
                    viewerCanUpdate: node["viewerCanUpdate"]?.bool ?? false,
                    viewerCanDelete: node["viewerCanDelete"]?.bool ?? false
                ))
            case "PullRequestReview":
                return .review(.init(id: id, createdAt: createdAt, author: Self.parseUser(node["author"]),
                                     state: node["state"]?.string ?? "COMMENTED", body: node["body"]?.string ?? ""))
            case "PullRequestCommit":
                let commit = node["commit"]
                return .commit(.init(id: id, createdAt: commit?["committedDate"]?.string ?? "",
                                     oidShort: commit?["abbreviatedOid"]?.string ?? "",
                                     messageHeadline: commit?["messageHeadline"]?.string ?? "",
                                     authorName: commit?["author"]?["name"]?.string ?? ""))
            case "MergedEvent":
                return .stateChange(.init(id: id, createdAt: createdAt, actor: Self.parseUser(node["actor"]),
                                          action: .merged(into: node["mergeRefName"]?.string ?? "base")))
            case "ClosedEvent":
                return .stateChange(.init(id: id, createdAt: createdAt, actor: Self.parseUser(node["actor"]), action: .closed))
            case "ReopenedEvent":
                return .stateChange(.init(id: id, createdAt: createdAt, actor: Self.parseUser(node["actor"]), action: .reopened))
            default:
                return nil
            }
        }

        // GitHub records a ClosedEvent alongside every MergedEvent; the web UI shows only the merge, so do the same.
        let isMerged = timeline.contains { if case .stateChange(let c) = $0, case .merged = c.action { return true } else { return false } }
        let visibleTimeline = isMerged
            ? timeline.filter { if case .stateChange(let c) = $0, c.action == .closed { return false } else { return true } }
            : timeline

        let milestone: MilestoneSummary? = item["milestone"].flatMap { m in
            guard let number = m["number"]?.int, let title = m["title"]?.string else { return nil }
            return MilestoneSummary(number: number, title: title, description: m["description"]?.string,
                                    state: m["state"]?.string ?? "OPEN", dueOn: m["dueOn"]?.string)
        }
        let reviewers = (item["reviewRequests"]?["nodes"]?.items ?? []).compactMap { node -> UserSummary? in
            guard let reviewer = node["requestedReviewer"], reviewer["login"]?.string?.isEmpty == false else { return nil }
            return Self.parseUser(reviewer)
        }

        return IssueOrPullDetail(
            id: item["id"]?.string ?? "",
            number: item["number"]?.int ?? ref.number,
            title: item["title"]?.string ?? "",
            body: item["body"]?.string ?? "",
            kind: isPR ? .pullRequest : .issue,
            state: IssueOrPullState(raw: item["state"]?.string),
            isDraft: item["isDraft"]?.bool ?? false,
            repoOwner: ref.owner,
            repoName: ref.repo,
            author: Self.parseUser(item["author"]),
            createdAt: item["createdAt"]?.string ?? "",
            updatedAt: item["updatedAt"]?.string ?? "",
            labels: Self.parseLabels(item["labels"]?["nodes"]),
            assignees: (item["assignees"]?["nodes"]?.items ?? []).map { Self.parseUser($0) },
            milestone: milestone,
            headRefName: item["headRefName"]?.string,
            baseRefName: item["baseRefName"]?.string,
            additions: item["additions"]?.int ?? 0,
            deletions: item["deletions"]?.int ?? 0,
            changedFilesCount: item["changedFiles"]?.int ?? 0,
            mergeable: item["mergeable"]?.string,
            mergeStateStatus: item["mergeStateStatus"]?.string,
            reviewDecision: item["reviewDecision"]?.string,
            checkRollup: Self.checkRollupState(item),
            htmlURL: item["url"]?.string ?? "",
            timeline: visibleTimeline,
            viewerPermission: permission,
            viewerCanUpdate: canUpdate,
            viewerCanCloseOrReopen: canUpdate || canTriage,
            viewerCanMerge: canWrite,
            viewerCanEditMetadata: canTriage,
            headRefOid: item["headRefOid"]?.string,
            reactions: Self.parseReactionGroups(item["reactionGroups"]),
            requestedReviewers: reviewers
        )
    }

    func pullFiles(_ ref: IssueRef) async throws -> [PullFileChange] {
        let json = try await client.json(.get, "\(APIPath.repo(ref.owner, ref.repo))/pulls/\(ref.number)/files",
                                         query: ["per_page": "100"], failure: String(localized: "Failed to load PR files"))
        return json.items.map(Self.parseFileChange)
    }

    static func parseFileChange(_ obj: JSONValue) -> PullFileChange {
        let patch = obj["patch"]?.string
        return PullFileChange(
            filename: obj["filename"]?.string ?? "",
            previousFilename: obj["previous_filename"]?.string,
            status: FileChangeStatus(raw: obj["status"]?.string ?? "modified"),
            additions: obj["additions"]?.int ?? 0,
            deletions: obj["deletions"]?.int ?? 0,
            patch: patch,
            hunks: DiffParser.parse(patch)
        )
    }

    // MARK: Mutations

    func postComment(_ ref: IssueRef, body: String) async throws {
        try await client.expectSuccess(.post, "\(APIPath.repo(ref.owner, ref.repo))/issues/\(ref.number)/comments",
                                       body: ["body": .string(body)], failure: String(localized: "Failed to post comment"))
    }

    func setState(_ ref: IssueRef, open: Bool) async throws {
        try await client.expectSuccess(.patch, "\(APIPath.repo(ref.owner, ref.repo))/issues/\(ref.number)",
                                       body: ["state": .string(open ? "open" : "closed")], failure: String(localized: "Failed to update state"))
    }

    func createIssue(_ repo: RepoRef, title: String, body: String, labels: [String] = []) async throws -> Int {
        var payload: [String: JSONValue] = ["title": .string(title), "body": .string(body)]
        let clean = Array(Set(labels.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }))
        if !clean.isEmpty { payload["labels"] = .array(clean.sorted().map { .string($0) }) }
        let json = try await client.json(.post, "\(APIPath.repo(repo.owner, repo.name))/issues", body: .object(payload),
                                         failure: String(localized: "Failed to create issue"))
        return json["number"]?.int ?? 0
    }

    func submitReview(_ ref: IssueRef, event: ReviewEvent, body: String) async throws {
        try await client.expectSuccess(.post, "\(APIPath.repo(ref.owner, ref.repo))/pulls/\(ref.number)/reviews",
                                       body: ["event": .string(event.rawValue), "body": .string(body)],
                                       failure: String(localized: "Failed to submit review"))
    }

    func merge(_ ref: IssueRef, method: MergeMethod, commitTitle: String? = nil) async throws {
        var payload: [String: JSONValue] = ["merge_method": .string(method.rawValue)]
        if let commitTitle, !commitTitle.isEmpty { payload["commit_title"] = .string(commitTitle) }
        try await client.expectSuccess(.put, "\(APIPath.repo(ref.owner, ref.repo))/pulls/\(ref.number)/merge",
                                       body: .object(payload), failure: String(localized: "Merge failed"))
    }

    func toggleReaction(subjectID: String, content: String, currentlyReacted: Bool) async throws {
        guard let reaction = ReactionContent(rawValue: content.uppercased()) else { return }
        let op = currentlyReacted ? "removeReaction" : "addReaction"
        _ = try await client.graphQL("""
            mutation($subjectId: ID!) {
              \(op)(input: { subjectId: $subjectId, content: \(reaction.rawValue) }) { reaction { content } }
            }
            """, variables: ["subjectId": .string(subjectID)])
    }

    func updateComment(id: String, body: String) async throws {
        _ = try await client.graphQL("""
            mutation($id: ID!, $body: String!) {
              updateIssueComment(input: { id: $id, body: $body }) { issueComment { id } }
            }
            """, variables: ["id": .string(id), "body": .string(body)])
    }

    func deleteComment(id: String) async throws {
        _ = try await client.graphQL("""
            mutation($id: ID!) { deleteIssueComment(input: { id: $id }) { clientMutationId } }
            """, variables: ["id": .string(id)])
    }

    func setDraft(pullRequestID: String, draft: Bool) async throws {
        let op = draft ? "convertPullRequestToDraft" : "markPullRequestReadyForReview"
        _ = try await client.graphQL("""
            mutation($id: ID!) { \(op)(input: { pullRequestId: $id }) { pullRequest { id isDraft } } }
            """, variables: ["id": .string(pullRequestID)])
    }

    func repoLabels(_ repo: RepoRef) async throws -> [LabelTag] {
        let json = try await client.json(.get, "\(APIPath.repo(repo.owner, repo.name))/labels", query: ["per_page": "100"],
                                         failure: String(localized: "Failed to load labels"))
        return json.items.compactMap { obj in
            guard let name = obj["name"]?.string else { return nil }
            return LabelTag(name: name, colorHex: obj["color"]?.string ?? "6750A4", description: obj["description"]?.string)
        }
    }
}
