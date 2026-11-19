import SwiftUI
import Observation

enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Accent presets, matching the curated seed colours of the Compose app.
enum AccentPreset: String, CaseIterable, Identifiable, Sendable {
    case system, purple, blue, teal, green, orange, pink, red
    var id: String { rawValue }

    var color: Color? {
        switch self {
        case .system: nil
        case .purple: Color(hex: "6750A4")
        case .blue: Color(hex: "0969DA")
        case .teal: Color(hex: "00897B")
        case .green: Color(hex: "1A7F37")
        case .orange: Color(hex: "E16F24")
        case .pink: Color(hex: "BF3989")
        case .red: Color(hex: "CF222E")
        }
    }
}

/// Non-sensitive preferences stored in `UserDefaults` (the session itself is in the Keychain).
@Observable
final class AppPreferences {
    @ObservationIgnored private let defaults: UserDefaults

    var customClientID: String { didSet { defaults.set(customClientID, forKey: Keys.clientID) } }
    var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) } }
    var accent: AccentPreset { didSet { defaults.set(accent.rawValue, forKey: Keys.accent) } }
    var pinnedRepos: [String] { didSet { defaults.set(pinnedRepos, forKey: Keys.pinned) } }
    var inboxFilter: InboxFilter { didSet { defaults.set(inboxFilter.rawValue, forKey: Keys.inboxFilter) } }
    var pollUnreadInForeground: Bool { didSet { defaults.set(pollUnreadInForeground, forKey: Keys.poll) } }
    var codeWrapLines: Bool { didSet { defaults.set(codeWrapLines, forKey: Keys.wrap) } }

    private enum Keys {
        static let clientID = "oauth.customClientID"
        static let appearance = "ui.appearance"
        static let accent = "ui.accent"
        static let pinned = "home.pinnedRepos"
        static let inboxFilter = "inbox.filter"
        static let poll = "inbox.pollForeground"
        static let wrap = "code.wrapLines"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        customClientID = defaults.string(forKey: Keys.clientID) ?? ""
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        accent = AccentPreset(rawValue: defaults.string(forKey: Keys.accent) ?? "") ?? .system
        pinnedRepos = defaults.stringArray(forKey: Keys.pinned) ?? []
        inboxFilter = InboxFilter(rawValue: defaults.string(forKey: Keys.inboxFilter) ?? "") ?? .unread
        pollUnreadInForeground = defaults.object(forKey: Keys.poll) as? Bool ?? true
        codeWrapLines = defaults.object(forKey: Keys.wrap) as? Bool ?? false
    }

    /// The Client ID used for new sign-ins: the custom one when set, otherwise the bundled default.
    var effectiveClientID: String {
        let trimmed = customClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppBranding.defaultOAuthClientID : trimmed
    }

    func isPinned(_ fullName: String) -> Bool {
        pinnedRepos.contains { $0.caseInsensitiveCompare(fullName) == .orderedSame }
    }

    func togglePinned(_ fullName: String) {
        if isPinned(fullName) {
            pinnedRepos.removeAll { $0.caseInsensitiveCompare(fullName) == .orderedSame }
        } else {
            pinnedRepos.append(fullName)
        }
    }

    /// Clears per-account state on sign-out.
    func resetAccountState() {
        pinnedRepos = []
    }
}
