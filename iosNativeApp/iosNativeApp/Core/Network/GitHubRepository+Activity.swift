import Foundation

extension GitHubRepository {
    /// Events from people and repositories the user follows ("Following" feed).
    func receivedEvents(_ login: String) async throws -> [ActivityEvent] {
        let json = try await client.json(.get, "users/\(APIPath.seg(login))/received_events", query: ["per_page": "40"],
                                         failure: String(localized: "Failed to load activity feed"))
        return json.items.compactMap(Self.parseActivityEvent)
    }

    /// Events performed by the user ("My activity" feed and profile pages).
    func userEvents(_ login: String) async throws -> [ActivityEvent] {
        let json = try await client.json(.get, "users/\(APIPath.seg(login))/events", query: ["per_page": "40"],
                                         failure: String(localized: "Failed to load user events"))
        return json.items.compactMap(Self.parseActivityEvent)
    }

    /// Port of `parseActivityEvent` in GitHubRestService.kt. Summaries are built in the UI so they can be localized.
    static func parseActivityEvent(_ dto: JSONValue) -> ActivityEvent? {
        guard let id = dto["id"]?.string else { return nil }
        let repoFull = dto["repo"]?["name"]?.string ?? ""
        let parts = repoFull.split(separator: "/", maxSplits: 1).map(String.init)
        let payload = dto["payload"]
        let actorLogin = dto["actor"]?["login"]?.string ?? "ghost"

        var event = ActivityEvent(
            id: id,
            kind: .other,
            actor: UserSummary(login: actorLogin, avatarURL: dto["actor"]?["avatar_url"]?.string ?? "", htmlURL: "https://github.com/\(actorLogin)"),
            repoFullName: repoFull,
            repoOwner: parts.first ?? "",
            repoName: parts.count > 1 ? parts[1] : repoFull,
            summaryText: "",
            createdAt: dto["created_at"]?.string ?? ""
        )
        let action = payload?["action"]?.string

        switch dto["type"]?.string ?? "" {
        case "PushEvent":
            event.kind = .push
            let branch = (payload?["ref"]?.string ?? "refs/heads/main").replacingOccurrences(of: "refs/heads/", with: "")
            event.branchName = branch
            let commits = payload?["commits"]?.items ?? []
            let size = payload?["size"]?.int ?? max(commits.count, 1)
            event.commitSHA = commits.first?["sha"]?.string ?? payload?["head"]?.string
            event.detailTitle = commits.first?["message"]?.string?.split(separator: "\n").first.map(String.init)
            event.summaryText = String(localized: "pushed \(size) commit(s) to \(branch)")
        case "PullRequestEvent":
            event.kind = .pullRequest
            let pr = payload?["pull_request"]
            event.targetIssueNumber = pr?["number"]?.int ?? payload?["number"]?.int
            event.detailTitle = pr?["title"]?.string
            let merged = pr?["merged_at"]?.string != nil
            let verb = action == "closed" && merged ? "merged" : (action ?? "updated")
            event.summaryText = String(localized: "\(verb) pull request \(numberSuffix(event.targetIssueNumber))")
        case "IssuesEvent":
            event.kind = .issues
            event.targetIssueNumber = payload?["issue"]?["number"]?.int
            event.detailTitle = payload?["issue"]?["title"]?.string
            event.summaryText = String(localized: "\(action ?? "updated") issue \(numberSuffix(event.targetIssueNumber))")
        case "IssueCommentEvent":
            event.kind = .issueComment
            event.targetIssueNumber = payload?["issue"]?["number"]?.int
            event.detailTitle = payload?["issue"]?["title"]?.string
            event.summaryText = String(localized: "commented on \(numberSuffix(event.targetIssueNumber))")
        case "PullRequestReviewEvent", "PullRequestReviewCommentEvent":
            event.kind = .pullRequestReview
            event.targetIssueNumber = payload?["pull_request"]?["number"]?.int
            event.detailTitle = payload?["pull_request"]?["title"]?.string
            let number = numberSuffix(event.targetIssueNumber)
            event.summaryText = switch payload?["review"]?["state"]?.string?.lowercased() {
            case "approved": String(localized: "approved pull request \(number)")
            case "changes_requested": String(localized: "requested changes on \(number)")
            default: String(localized: "reviewed pull request \(number)")
            }
        case "WatchEvent":
            event.kind = .watch
            event.summaryText = String(localized: "starred repository")
        case "ForkEvent":
            event.kind = .fork
            event.detailTitle = payload?["forkee"]?["full_name"]?.string
            event.summaryText = String(localized: "forked repository")
        case "CreateEvent":
            event.kind = .create
            let refType = payload?["ref_type"]?.string ?? "ref"
            let ref = payload?["ref"]?.string
            event.branchName = refType == "branch" ? ref : nil
            event.summaryText = ref.map { String(localized: "created \(refTypeName(refType)) \($0)") } ?? String(localized: "created repository")
        case "DeleteEvent":
            event.kind = .delete
            let refType = payload?["ref_type"]?.string ?? "ref"
            event.summaryText = String(localized: "deleted \(refTypeName(refType)) \(payload?["ref"]?.string ?? "")")
        case "ReleaseEvent":
            event.kind = .release
            let tag = payload?["release"]?["tag_name"]?.string
            event.releaseTag = tag
            event.detailTitle = payload?["release"]?["name"]?.string ?? tag
            event.summaryText = String(localized: "\(action ?? "published") release \(tag ?? "")")
        case "PublicEvent":
            event.kind = .public
            event.summaryText = String(localized: "made repository public")
        case "MemberEvent":
            event.kind = .member
            let member = payload?["member"]?["login"]?.string.map { "@\($0)" } ?? "collaborator"
            event.summaryText = "\(action ?? "added") \(member)"
        case let type:
            event.summaryText = type.hasSuffix("Event") ? String(type.dropLast(5)) : (type.isEmpty ? "activity" : type)
        }
        return event
    }

    private static func refTypeName(_ refType: String) -> String {
        switch refType {
        case "branch": String(localized: "branch")
        case "tag": String(localized: "tag")
        case "repository": String(localized: "repository")
        default: refType
        }
    }

    private static func numberSuffix(_ number: Int?) -> String {
        number.map { "#\($0)" } ?? ""
    }
}
