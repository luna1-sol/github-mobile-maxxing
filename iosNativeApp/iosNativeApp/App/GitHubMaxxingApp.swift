import SwiftUI
import SafariServices

@main
struct GitHubMaxxingApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .environment(environment.preferences)
                .tint(environment.preferences.accent.color)
                .preferredColorScheme(environment.preferences.appearance.colorScheme)
                .onOpenURL { url in
                    if environment.sessionManager.isSignedIn {
                        environment.router.open(url)
                    } else {
                        environment.router.pendingURL = url
                    }
                }
        }
    }
}

/// Chooses between session loading, the sign-in screen and the signed-in shell.
struct RootView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Group {
            if !env.sessionManager.isLoaded {
                ProgressView()
            } else if let error = env.sessionManager.loadError {
                ContentUnavailableView {
                    Label("Couldn't load your session", systemImage: "lock.trianglebadge.exclamationmark")
                } description: {
                    Text("Secure storage is unavailable: \(error). If the device was just restarted, unlock it and try again.")
                } actions: {
                    Button("Try again") { Task { await env.sessionManager.load() } }
                        .buttonStyle(.glassProminent)
                        .onAccentLabel()
                }
            } else if env.sessionManager.isSignedIn {
                MainTabView()
            } else {
                SignInScreen()
            }
        }
        .animation(.smooth, value: env.sessionManager.isSignedIn)
        .task { if !env.sessionManager.isLoaded { await env.sessionManager.load() } }
        .environment(\.openURL, OpenURLAction { url in
            if env.router.open(url) { return .handled }
            if url.scheme == "https" || url.scheme == "http" {
                env.router.openExternally(url)
                return .handled
            }
            return .systemAction
        })
        .sheet(item: Binding(
            get: { env.router.safariURL.map(IdentifiedURL.init) },
            set: { env.router.safariURL = $0?.url }
        )) { item in
            SafariView(url: item.url).ignoresSafeArea()
        }
    }
}

struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
