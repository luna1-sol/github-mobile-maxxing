import Foundation

/// Shared application identity (port of core/model AppBranding.kt).
enum AppBranding {
    static let appName = "github-mobile-maxxing"
    static let userAgent = "github-mobile-maxxing-iOS-native/1.0"
    static let defaultOAuthClientID = "Ov23lihCAIZTj1Puaf9r"
    static let repoOwner = "neutron42-jp"
    static let repoName = "github-mobile-maxxing"
    static let repositoryURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)")!
}
