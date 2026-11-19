import Foundation

/// Identity of Maxxing Glass, an unofficial SwiftUI derivative of github-mobile-maxxing.
enum AppBranding {
    static let appName = "Maxxing Glass"

    /// OAuth App used for Device Flow sign-in, from the `OAUTH_CLIENT_ID` build setting (Configuration/Config.xcconfig,
    /// overridable in Local.xcconfig). An empty value makes sign-in report a missing Client ID.
    static let defaultOAuthClientID: String = {
        let value = Bundle.main.object(forInfoDictionaryKey: "MaxxingOAuthClientID") as? String ?? ""
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    /// This app's source code.
    static let repositoryURL = URL(string: "https://github.com/luna1-sol/github-mobile-maxxing/tree/feat/ios-native-swiftui")!
    /// The project this app is derived from; its `core` modules provide all data access.
    static let upstreamRepositoryURL = URL(string: "https://github.com/neutron42-jp/github-mobile-maxxing")!
}
