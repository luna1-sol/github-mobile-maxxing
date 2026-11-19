import SwiftUI

/// Port of SettingsScreen.kt (account, appearance, notifications, general, app info), presented as a sheet from Home.
struct SettingsScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsSignOut = false
    @State private var showsClientID = false

    var body: some View {
        @Bindable var preferences = env.preferences

        NavigationStack {
            Form {
                accountSection

                Section("Appearance") {
                    Picker("Theme", selection: $preferences.appearance) {
                        Text("System").tag(AppearanceMode.system)
                        Text("Light").tag(AppearanceMode.light)
                        Text("Dark").tag(AppearanceMode.dark)
                    }
                    accentPicker
                }

                Section {
                    Toggle("Refresh unread count while open", isOn: $preferences.pollUnreadInForeground)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Checks GitHub for unread notifications every minute while the app is in the foreground.")
                }

                Section("General") {
                    Toggle("Wrap long lines in code", isOn: $preferences.codeWrapLines)
                    Button {
                        showsClientID = true
                    } label: {
                        LabeledContent("OAuth Client ID") {
                            Text(preferences.customClientID.isEmpty ? String(localized: "Default") : preferences.customClientID)
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(.primary)
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    let rate = env.repository.rateLimit
                    LabeledContent("API rate limit", value: "\(rate.remaining) / \(rate.limit)")
                    Button("Source code", systemImage: "chevron.left.forwardslash.chevron.right") {
                        env.router.openExternally(AppBranding.repositoryURL)
                    }
                    Button("Based on github-mobile-maxxing", systemImage: "arrow.triangle.branch") {
                        env.router.openExternally(AppBranding.upstreamRepositoryURL)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .sheet(isPresented: $showsClientID) { ClientIDSheet() }
            .confirmationDialog("Sign out of GitHub?", isPresented: $confirmsSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task {
                        dismiss()
                        await env.signOut()
                    }
                }
            } message: {
                Text("The token is removed from this device. You can revoke it from GitHub settings.")
            }
        }
    }

    private var accountSection: some View {
        Section("Account") {
            if let viewer = env.viewer {
                HStack(spacing: 14) {
                    AvatarView(url: viewer.avatarURL, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewer.name ?? viewer.login).font(.headline)
                        Text(viewer.login).foregroundStyle(.secondary)
                    }
                }
            }
            if let session = env.sessionManager.session {
                LabeledContent("Signed in with",
                               value: session.authMethod == .deviceFlow ? String(localized: "GitHub OAuth") : String(localized: "Personal access token"))
                if !session.scope.isEmpty {
                    LabeledContent("Scopes") {
                        Text(session.scope.replacingOccurrences(of: ",", with: ", "))
                            .multilineTextAlignment(.trailing)
                            .font(.footnote)
                    }
                }
            }
            Button("Sign out", role: .destructive) { confirmsSignOut = true }
        }
    }

    private var accentPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accent color")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(AccentPreset.allCases) { preset in
                        let selected = env.preferences.accent == preset
                        Button {
                            env.preferences.accent = preset
                        } label: {
                            Circle()
                                .fill(preset.color ?? Color("AccentColor"))
                                .overlay {
                                    if preset == .system {
                                        Image(systemName: "iphone").font(.caption).foregroundStyle(.white)
                                    }
                                }
                                .frame(width: 32, height: 32)
                                .padding(4)
                                .overlay(Circle().stroke(selected ? Color.primary : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preset.rawValue.capitalized)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
