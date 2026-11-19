import SwiftUI
import Observation

/// Drives the Device Flow polling loop (port of the flow in DeviceFlowClient.kt / SignInScreen.kt).
@Observable
final class SignInModel {
    enum Phase: Equatable {
        case idle
        case requestingCode
        case awaitingUser(DeviceFlowClient.DeviceCode, status: Status)
        case verifying
        case failed(String)
    }

    enum Status: Equatable {
        case codeIssued, pending, networkRetry, slowDown(Int)
    }

    var phase: Phase = .idle
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let client = DeviceFlowClient()

    func start(clientID: String, onSession: @escaping (AuthSession) throws -> Void) {
        cancel()
        task = Task {
            phase = .requestingCode
            do {
                let code = try await client.requestDeviceCode(clientID: clientID)
                phase = .awaitingUser(code, status: .codeIssued)
                var interval = code.interval
                var elapsed = 0
                while elapsed < code.expiresIn {
                    try await Task.sleep(for: .seconds(interval))
                    elapsed += interval
                    let result: DeviceFlowClient.PollResult
                    do {
                        result = try await client.pollAccessToken(clientID: clientID, deviceCode: code.deviceCode)
                    } catch is CancellationError {
                        return
                    } catch {
                        phase = .awaitingUser(code, status: .networkRetry)
                        continue
                    }
                    switch result {
                    case .authorized(let session):
                        phase = .verifying
                        try onSession(session)
                        return
                    case .pending:
                        phase = .awaitingUser(code, status: .pending)
                    case .slowDown(let newInterval):
                        interval = newInterval ?? interval + 5
                        phase = .awaitingUser(code, status: .slowDown(interval))
                    case .expired:
                        phase = .failed(String(localized: "The device code expired. Request a new code."))
                        return
                    case .denied:
                        phase = .failed(String(localized: "Authorization was denied in the browser."))
                        return
                    case .failed(_, let description):
                        phase = .failed(description)
                        return
                    }
                }
                phase = .failed(String(localized: "Device code timed out. Please try again."))
            } catch is CancellationError {
                return
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
    }
}

struct SignInScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL
    @State private var model = SignInModel()
    @State private var showsPAT = false
    @State private var showsClientID = false
    @State private var copied = false
    @Namespace private var glassNamespace

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    GlassEffectContainer(spacing: 16) {
                        VStack(spacing: 16) {
                            content
                        }
                    }
                    .animation(.smooth, value: model.phase)
                }
                .padding(24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(backgroundGradient.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Sign in with a personal access token", systemImage: "key") { showsPAT = true }
                        Button("OAuth Client ID…", systemImage: "gearshape") { showsClientID = true }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More sign-in options")
                }
            }
            .sheet(isPresented: $showsPAT) { PersonalAccessTokenSheet() }
            .sheet(isPresented: $showsClientID) { ClientIDSheet() }
        }
        .onDisappear { model.cancel() }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 96, height: 96)
                .glassEffect(.regular.tint(.accentColor.opacity(0.15)), in: .rect(cornerRadius: 28))
            Text(AppBranding.appName)
                .font(.title.bold())
            Text("A fast GitHub client. Sign in with your GitHub account to continue.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 32)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .failed:
            if case .failed(let message) = model.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .glassPanel(cornerRadius: 20, tint: .red.opacity(0.08))
            }
            Button {
                model.start(clientID: env.preferences.effectiveClientID, onSession: signIn)
            } label: {
                Label("Sign in with GitHub", systemImage: "person.badge.key")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .glassEffectID("primary", in: glassNamespace)
            if !env.preferences.customClientID.isEmpty {
                Text("Using custom Client ID \(env.preferences.effectiveClientID)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .requestingCode, .verifying:
            ProgressView(model.phase == .verifying ? "Signing in…" : "Requesting a code…")
                .padding(24)
                .frame(maxWidth: .infinity)
                .glassPanel()
                .glassEffectID("primary", in: glassNamespace)
        case .awaitingUser(let code, let status):
            codePanel(code, status: status)
                .glassEffectID("primary", in: glassNamespace)
            Button("Cancel", role: .cancel) { model.cancel() }
                .buttonStyle(.glass)
        }
    }

    private func codePanel(_ code: DeviceFlowClient.DeviceCode, status: SignInModel.Status) -> some View {
        VStack(spacing: 16) {
            Text("Enter this code on GitHub")
                .font(.headline)
            Text(code.userCode)
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .kerning(4)
                .textSelection(.enabled)
                .accessibilityLabel(Text(code.userCode.map(String.init).joined(separator: " ")))
            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = code.userCode
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.glass)
                Button {
                    UIPasteboard.general.string = code.userCode
                    if let url = URL(string: code.verificationURI) { openURL(url) }
                } label: {
                    Label("Open GitHub", systemImage: "safari")
                }
                .buttonStyle(.glassProminent)
            }
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(statusText(status))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassPanel(cornerRadius: 28)
    }

    private func statusText(_ status: SignInModel.Status) -> LocalizedStringKey {
        switch status {
        case .codeIssued: "Copy the code, then authorize in the browser."
        case .pending: "Waiting for browser authorization…"
        case .networkRetry: "Temporary network hiccup, retrying…"
        case .slowDown(let seconds): "Rate limited by GitHub; polling every \(seconds)s…"
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(colors: [Color.accentColor.opacity(0.25), .clear], startPoint: .top, endPoint: .center)
    }

    private func signIn(_ session: AuthSession) throws {
        try env.sessionManager.signIn(session)
    }
}

private struct PersonalAccessTokenSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var isVerifying = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("ghp_… or github_pat_…", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                } footer: {
                    Text("Recommended scopes: repo, gist, notifications, read:user, user:follow, read:org. The token is stored in the iOS Keychain.")
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
            }
            .navigationTitle("Personal access token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isVerifying {
                        ProgressView()
                    } else {
                        Button("Sign in", systemImage: "checkmark") { Task { await verify() } }
                            .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func verify() async {
        isVerifying = true
        defer { isVerifying = false }
        do {
            let session = try await DeviceFlowClient().verifyPersonalAccessToken(token)
            try env.sessionManager.signIn(session)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ClientIDSheet: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(AppBranding.defaultOAuthClientID, text: $draft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                } footer: {
                    Text("Leave empty to use the built-in Client ID. Your OAuth or GitHub App must have Device Flow enabled.")
                }
            }
            .navigationTitle("OAuth Client ID")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        preferences.customClientID = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { draft = preferences.customClientID }
    }
}
