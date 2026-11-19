import Foundation

extension GitHubRepository {
    func notifications(filter: InboxFilter, page: Int = 1) async throws -> [NotificationThread] {
        let json = try await client.json(
            .get, "notifications",
            query: [
                "all": filter == .all ? "true" : "false",
                "participating": filter == .participating ? "true" : "false",
                "page": String(page),
                "per_page": "50",
            ],
            noCache: true,
            failure: String(localized: "Failed to load notifications"))
        return json.items.compactMap(Self.parseNotification)
    }

    /// Number of unread threads on the first page, used for the Inbox tab badge.
    func unreadNotificationCount() async throws -> Int {
        try await notifications(filter: .unread).filter(\.unread).count
    }

    func markNotificationRead(_ threadID: String) async throws {
        try await client.expectSuccess(.patch, "notifications/threads/\(APIPath.seg(threadID))", failure: String(localized: "Failed to mark thread read"))
    }

    func markNotificationDone(_ threadID: String) async throws {
        try await client.expectSuccess(.delete, "notifications/threads/\(APIPath.seg(threadID))", failure: String(localized: "Failed to mark thread done"))
    }

    func markAllNotificationsRead() async throws {
        try await client.expectSuccess(.put, "notifications", body: ["read": true], failure: String(localized: "Failed to mark all notifications read"))
    }

    static func parseNotification(_ obj: JSONValue) -> NotificationThread? {
        guard let id = obj["id"]?.string, let repo = obj["repository"], let subject = obj["subject"] else { return nil }
        let full = repo["full_name"]?.string ?? ""
        return NotificationThread(
            id: id,
            unread: obj["unread"]?.bool ?? false,
            reason: NotificationReason(raw: obj["reason"]?.string?.lowercased() ?? ""),
            updatedAt: obj["updated_at"]?.string ?? "",
            subjectTitle: subject["title"]?.string ?? "",
            subjectType: NotificationSubjectType(raw: subject["type"]?.string ?? ""),
            subjectURL: subject["url"]?.string,
            latestCommentURL: subject["latest_comment_url"]?.string,
            repoFullName: full,
            repoOwner: repo["owner"]?["login"]?.string ?? String(full.split(separator: "/").first ?? ""),
            repoName: repo["name"]?.string ?? "",
            repoOwnerAvatarURL: repo["owner"]?["avatar_url"]?.string ?? "",
            isPrivate: repo["private"]?.bool ?? false
        )
    }
}
