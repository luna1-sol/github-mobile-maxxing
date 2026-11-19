import Foundation

/// Localizes the English activity summaries produced by core/network (`GitHubRestService.parseActivityEvent`),
/// following core/ui `AppStrings.translatedActivity`. Unrecognized summaries are shown as-is.
enum ActivitySummary {
    static func localized(kind: ActivityEventKind, summary: String, number: Int?, branch: String?, releaseTag: String?) -> String {
        let ref = number.map { "#\($0)" } ?? ""
        func verb(before marker: String) -> String? {
            guard let range = summary.range(of: marker) else { return nil }
            return String(summary[..<range.lowerBound])
        }

        switch kind {
        case .push:
            guard let match = summary.firstMatch(of: #/pushed (\d+) commit/#), let count = Int(match.1) else { return summary }
            let target = branch ?? summary.components(separatedBy: " to ").last ?? ""
            return String(localized: "pushed \(count) commit(s) to \(target)")
        case .pullRequest:
            switch verb(before: " pull request") ?? (summary.hasSuffix("pull request") ? String(summary.dropLast(" pull request".count)) : nil) {
            case "opened": return trimmed(String(localized: "opened pull request \(ref)"))
            case "merged": return trimmed(String(localized: "merged pull request \(ref)"))
            case "closed": return trimmed(String(localized: "closed pull request \(ref)"))
            case "reopened": return trimmed(String(localized: "reopened pull request \(ref)"))
            case .some: return trimmed(String(localized: "updated pull request \(ref)"))
            case nil: return summary
            }
        case .issues:
            switch verb(before: " issue") ?? (summary.hasSuffix("issue") ? String(summary.dropLast(" issue".count)) : nil) {
            case "opened": return trimmed(String(localized: "opened issue \(ref)"))
            case "closed": return trimmed(String(localized: "closed issue \(ref)"))
            case "reopened": return trimmed(String(localized: "reopened issue \(ref)"))
            case .some: return trimmed(String(localized: "updated issue \(ref)"))
            case nil: return summary
            }
        case .issueComment:
            if summary == "commented on thread" || number == nil { return String(localized: "commented on a thread") }
            return String(localized: "commented on \(ref)")
        case .pullRequestReview:
            if summary.hasPrefix("approved") { return trimmed(String(localized: "approved pull request \(ref)")) }
            if summary.hasPrefix("requested changes") { return trimmed(String(localized: "requested changes on \(ref)")) }
            if summary.hasPrefix("reviewed") { return trimmed(String(localized: "reviewed pull request \(ref)")) }
            return summary
        case .watch:
            return String(localized: "starred repository")
        case .fork:
            return String(localized: "forked repository")
        case .create, .delete:
            let prefix = kind == .create ? "created " : "deleted "
            guard summary.hasPrefix(prefix) else { return summary }
            let rest = summary.dropFirst(prefix.count).split(separator: " ", maxSplits: 1).map(String.init)
            if kind == .create && rest == ["repository"] { return String(localized: "created repository") }
            guard let refType = rest.first else { return summary }
            let name = rest.count > 1 ? rest[1] : ""
            return kind == .create
                ? trimmed(String(localized: "created \(refTypeName(refType)) \(name)"))
                : trimmed(String(localized: "deleted \(refTypeName(refType)) \(name)"))
        case .release:
            guard let action = verb(before: " release") ?? (summary.hasSuffix("release") ? String(summary.dropLast(" release".count)) : nil) else {
                return summary
            }
            let tag = releaseTag ?? ""
            if action == "published" || action == "released" { return trimmed(String(localized: "published release \(tag)")) }
            return trimmed(String(localized: "\(action) release \(tag)"))
        case .public:
            return String(localized: "made repository public")
        case .member, .other:
            return summary
        }
    }

    private static func refTypeName(_ refType: String) -> String {
        switch refType {
        case "branch": String(localized: "branch")
        case "tag": String(localized: "tag")
        case "repository": String(localized: "repository")
        default: refType
        }
    }

    /// Cleans up the gap left when the number or tag is unknown (e.g. "opened pull request ").
    private static func trimmed(_ text: String) -> String {
        text.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }
}
