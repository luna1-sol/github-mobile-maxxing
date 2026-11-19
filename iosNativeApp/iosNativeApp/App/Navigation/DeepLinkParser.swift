import Foundation

/// In-app destinations reachable from URLs (port of `AppDeepLink` in GitHubUrlParser.kt).
enum AppDeepLink: Equatable {
    case issueOrPull(IssueRef, fromNotification: Bool)
    case repository(RepoRef)
    case user(String)
    case externalWeb(URL)
}

enum DeepLinkParser {
    static let scheme = "githubmaxxing"
    static let threadHost = "thread"

    /// Strict parser for `githubmaxxing://thread/{owner}/{repo}/{number}` (port of `parseStrictDeepLink`).
    ///
    /// Scheme and host are case-insensitive; no user-info or port; exactly three non-empty path segments
    /// (one trailing slash tolerated); the number is ASCII digits only and positive; owner/repo are strict
    /// UTF-8 percent-decoded and contain no `/`, whitespace or control characters. Query and fragment are ignored.
    static func parseStrict(_ url: String?) -> IssueRef? {
        guard let raw = url, let sep = raw.range(of: "://") else { return nil }
        guard raw[..<sep.lowerBound].caseInsensitiveCompare(scheme) == .orderedSame,
              !raw[..<sep.lowerBound].isEmpty else { return nil }

        var remainder = Substring(raw[sep.upperBound...])
        if let end = remainder.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            remainder = remainder[..<end]
        }
        guard let slash = remainder.firstIndex(of: "/"), slash != remainder.startIndex,
              remainder[..<slash].caseInsensitiveCompare(threadHost) == .orderedSame else { return nil }

        var segments = remainder[remainder.index(after: slash)...].split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if segments.last == "" { segments.removeLast() }
        guard segments.count == 3, !segments.contains(where: \.isEmpty) else { return nil }

        guard let owner = percentDecodeStrict(segments[0]), isValidOwnerOrRepo(owner),
              let repo = percentDecodeStrict(segments[1]), isValidOwnerOrRepo(repo),
              let numberText = percentDecodeStrict(segments[2]), !numberText.isEmpty,
              numberText.allSatisfy({ $0.isASCII && $0.isNumber }),
              // 32-bit like Kotlin's toIntOrNull, so both apps accept exactly the same links.
              let number32 = Int32(numberText), number32 > 0
        else { return nil }
        return IssueRef(owner: owner, repo: repo, number: Int(number32))
    }

    /// Canonical deep link for a thread, or nil without a valid number (never `.../null`).
    static func threadURL(owner: String, repo: String, number: Int?) -> String? {
        guard let number, number > 0 else { return nil }
        let o = owner.trimmingCharacters(in: .whitespaces)
        let r = repo.trimmingCharacters(in: .whitespaces)
        guard isValidOwnerOrRepo(o), isValidOwnerOrRepo(r) else { return nil }
        return "\(scheme)://\(threadHost)/\(encodeSegment(o))/\(encodeSegment(r))/\(number)"
    }

    private static func isValidOwnerOrRepo(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespaces).isEmpty
            && !value.contains("/")
            && !value.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }
    }

    private static func encodeSegment(_ value: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    /// Strict UTF-8 percent decoding; nil for a malformed escape or invalid UTF-8.
    static func percentDecodeStrict(_ value: String) -> String? {
        guard value.contains("%") else { return value }
        var bytes: [UInt8] = []
        var index = value.startIndex
        while index < value.endIndex {
            let char = value[index]
            if char == "%" {
                guard let hi = value.index(index, offsetBy: 1, limitedBy: value.endIndex), hi < value.endIndex,
                      let lo = value.index(index, offsetBy: 2, limitedBy: value.endIndex), lo < value.endIndex,
                      let byte = UInt8(String(value[hi...lo]), radix: 16),
                      value[hi].isHexDigit, value[lo].isHexDigit
                else { return nil }
                bytes.append(byte)
                index = value.index(after: lo)
            } else {
                bytes.append(contentsOf: Array(String(char).utf8))
                index = value.index(after: index)
            }
        }
        return String(validating: bytes, as: UTF8.self)
    }
}

/// Parses `https://github.com/...` links into in-app destinations (port of `parseAppDeepLink`).
enum GitHubUrlParser {
    private static let reservedRootPaths: Set<String> = [
        "about", "apps", "codespaces", "collections", "contact", "copilot", "dashboard", "enterprise", "events",
        "explore", "features", "gist", "gists", "issues", "join", "login", "logout", "marketplace", "new",
        "notifications", "orgs", "organizations", "pricing", "pulls", "readme", "search", "security", "settings",
        "signup", "site", "solutions", "sponsors", "stars", "topics", "trending", "users", "watching",
    ]

    static func parse(_ url: URL) -> AppDeepLink? {
        if url.scheme?.lowercased() == DeepLinkParser.scheme {
            return DeepLinkParser.parseStrict(url.absoluteString).map { .issueOrPull($0, fromNotification: true) }
        }
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host()?.lowercased(), host == "github.com" || host == "www.github.com" else { return nil }

        let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let first = segments.first, !reservedRootPaths.contains(first.lowercased()) else {
            return .externalWeb(url)
        }
        if segments.count == 1 { return .user(first) }

        var repo = segments[1]
        if repo.hasSuffix(".git") { repo.removeLast(4) }
        guard !repo.isEmpty else { return .externalWeb(url) }

        if segments.count >= 4, segments[2] == "issues" || segments[2] == "pull",
           let number = Int(segments[3]), number > 0 {
            return .issueOrPull(IssueRef(owner: first, repo: repo, number: number), fromNotification: false)
        }
        return .repository(RepoRef(owner: first, name: repo))
    }
}
