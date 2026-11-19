import Foundation

// Port of core/model/src/commonMain/kotlin/dev/maxxing/github/model/UserModels.kt

struct UserSummary: Hashable, Codable, Sendable, Identifiable {
    var login: String
    var avatarURL: String = ""
    var htmlURL: String = ""
    var id: String { login }

    static let ghost = UserSummary(login: "ghost")
}

struct ViewerProfile: Hashable, Sendable {
    var login: String
    var name: String?
    var avatarURL: String = ""
    var bio: String?
    var company: String?
    var location: String?
    var followersCount = 0
    var followingCount = 0
    var publicReposCount = 0
    var htmlURL: String = ""
}

struct OrganizationSummary: Hashable, Sendable, Identifiable {
    var login: String
    var avatarURL: String = ""
    var description: String?
    var id: String { login }
}

struct UserProfile: Hashable, Sendable {
    var login: String
    var name: String?
    var avatarURL: String = ""
    var bio: String?
    var company: String?
    var location: String?
    var blogURL: String?
    var twitterUsername: String?
    var email: String?
    var followersCount = 0
    var followingCount = 0
    var publicReposCount = 0
    var publicGistsCount = 0
    var isOrganization = false
    var viewerIsFollowing = false
    var createdAt: String = ""
    var htmlURL: String = ""
}
