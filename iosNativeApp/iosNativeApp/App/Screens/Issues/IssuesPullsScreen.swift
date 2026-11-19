import SwiftUI

/// Port of IssuesPullsScreen.kt: the viewer's issues and PRs by preset (created / assigned / review requested / mentioned).
struct IssuesPullsScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var preset: IssueFilterPreset = .created
    @State private var stateFilter: IssueStateFilter = .open
    @State private var state: LoadState<[IssueOrPullSummary]> = .loading
    @State private var isSwitching = false

    private struct Key: Hashable {
        var login: String?
        var preset: IssueFilterPreset
        var state: IssueStateFilter
    }

    var body: some View {
        AsyncContent(state, emptyTitle: "No matching issues or pull requests", emptySystemImage: "checkmark.circle",
                     retry: { await load(force: true) }, isRefreshing: isSwitching) { items in
            List(items) { item in
                NavigationLink(value: Route.issue(item.ref)) { IssueRow(item: item) }
            }
            .listStyle(.plain)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            FilterChips(selection: $preset, options: IssueFilterPreset.allCases) { preset in
                switch preset {
                case .created: "Created"
                case .assigned: "Assigned"
                case .reviewRequested: "Review requests"
                case .mentioned: "Mentioned"
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle("Issues & PRs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                StateFilterMenu(selection: $stateFilter)
            }
        }
        .refreshable { await load(force: true) }
        .task(id: Key(login: env.viewerLogin, preset: preset, state: stateFilter)) {
            guard state.value != nil else { return await load() }
            isSwitching = true
            defer { isSwitching = false }
            await load(replacing: true)
        }
    }

    private func load(replacing: Bool = false, force: Bool = false) async {
        guard let login = env.viewerLogin else { return }
        let preset = preset, stateFilter = stateFilter
        let operation = { try await env.repository.myIssuesAndPulls(preset: preset, viewerLogin: login, state: stateFilter, forceRefresh: force) }
        if replacing { await replaceState($state, operation) } else { await loadState($state, operation) }
    }
}

struct StateFilterMenu: View {
    @Binding var selection: IssueStateFilter

    var body: some View {
        Menu {
            Picker("State", selection: $selection) {
                Label("Open", systemImage: "circle.circle").tag(IssueStateFilter.open)
                Label("Closed", systemImage: "checkmark.circle").tag(IssueStateFilter.closed)
                Label("All", systemImage: "line.3.horizontal.decrease").tag(IssueStateFilter.all)
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .accessibilityLabel("Filter by state")
    }
}

/// Issues or pull requests of one repository.
struct RepoIssuesScreen: View {
    let repo: RepoRef
    let pullRequests: Bool

    @Environment(AppEnvironment.self) private var env
    @State private var stateFilter: IssueStateFilter = .open
    @State private var state: LoadState<[IssueOrPullSummary]> = .loading
    @State private var showsNewIssue = false
    @State private var isSwitching = false

    var body: some View {
        AsyncContent(state, emptyTitle: pullRequests ? "No pull requests" : "No issues", emptySystemImage: "tray",
                     retry: { await load(force: true) }, isRefreshing: isSwitching) { items in
            List(items) { item in
                NavigationLink(value: Route.issue(item.ref)) { IssueRow(item: item, showsRepo: false) }
            }
            .listStyle(.plain)
        }
        .navigationTitle(pullRequests ? "Pull requests" : "Issues")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { StateFilterMenu(selection: $stateFilter) }
            if !pullRequests {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New issue", systemImage: "plus") { showsNewIssue = true }
                }
            }
        }
        .sheet(isPresented: $showsNewIssue) {
            NewIssueSheet(repo: repo) { number in
                env.router.push(.issue(IssueRef(owner: repo.owner, repo: repo.name, number: number)))
            }
        }
        .refreshable { await load(force: true) }
        .task(id: stateFilter) {
            guard state.value != nil else { return await load() }
            isSwitching = true
            defer { isSwitching = false }
            await load(replacing: true)
        }
    }

    private func load(replacing: Bool = false, force: Bool = false) async {
        let stateFilter = stateFilter
        let operation = { try await env.repository.repoIssuesOrPulls(repo, pullRequests: pullRequests, state: stateFilter, forceRefresh: force) }
        if replacing { await replaceState($state, operation) } else { await loadState($state, operation) }
    }
}

/// Issue creation with optional labels (port of the create-issue flow in ReposScreen.kt).
struct NewIssueSheet: View {
    let repo: RepoRef
    var onCreated: (Int) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bodyText = ""
    @State private var labels: [LabelTag] = []
    @State private var selectedLabels: Set<String> = []
    @State private var isSubmitting = false
    @State private var error: String?
    @State private var preview = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                }
                Section {
                    Picker("Mode", selection: $preview) {
                        Text("Write").tag(false)
                        Text("Preview").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                    if preview {
                        MarkdownView(markdown: bodyText.isEmpty ? String(localized: "Nothing to preview") : bodyText)
                            .frame(minHeight: 160, alignment: .topLeading)
                    } else {
                        TextEditor(text: $bodyText)
                            .frame(minHeight: 200)
                            .font(.body.monospaced())
                    }
                } header: {
                    Text("Description")
                }
                if !labels.isEmpty {
                    Section("Labels") {
                        ForEach(labels) { label in
                            Button {
                                if selectedLabels.contains(label.name) { selectedLabels.remove(label.name) } else { selectedLabels.insert(label.name) }
                            } label: {
                                HStack {
                                    LabelChip(label: label)
                                    Spacer()
                                    if selectedLabels.contains(label.name) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("New issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Create", systemImage: "checkmark") { Task { await submit() } }
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .task { labels = (try? await env.repository.repoLabels(repo)) ?? [] }
            .errorAlert($error)
        }
        .interactiveDismissDisabled(!title.isEmpty || !bodyText.isEmpty)
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let number = try await env.repository.createIssue(repo, title: title.trimmingCharacters(in: .whitespaces),
                                                              body: bodyText, labels: Array(selectedLabels))
            dismiss()
            onCreated(number)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
