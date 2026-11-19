import Foundation

// Port of core/model/src/commonMain/kotlin/dev/maxxing/github/model/SearchModels.kt

enum GlobalSearchKind: String, CaseIterable, Hashable, Sendable {
    case repositories, issuesPRs, code, users
}

struct CodeSearchHit: Hashable, Sendable, Identifiable {
    var name: String
    var path: String
    var sha: String
    var repoFullName: String
    var repoOwner: String
    var repoName: String
    var htmlURL = ""
    var fragments: [String] = []
    var id: String { "\(repoFullName)/\(path)@\(sha)" }
}
