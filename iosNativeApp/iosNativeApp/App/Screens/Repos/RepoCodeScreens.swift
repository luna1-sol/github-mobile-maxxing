import SwiftUI

/// File tree of one directory.
struct DirectoryScreen: View {
    let repo: RepoRef
    let path: String
    let ref: String?

    @Environment(AppEnvironment.self) private var env
    @State private var state: LoadState<[TreeEntry]> = .loading

    var body: some View {
        AsyncContent(state, emptyTitle: "Empty directory", emptySystemImage: "folder", retry: { await load(force: true) }) { entries in
            List(entries) { entry in
                NavigationLink(value: entry.type == .tree
                               ? Route.directory(repo, path: entry.path, ref: ref)
                               : Route.file(repo, path: entry.path, ref: ref)) {
                    HStack(spacing: 12) {
                        Image(systemName: entry.type == .tree ? "folder.fill" : FileIcon.symbol(for: entry.name))
                            .foregroundStyle(entry.type == .tree ? Color.accentColor : .secondary)
                            .frame(width: 22)
                        Text(entry.name).lineLimit(1)
                        Spacer()
                        if entry.type == .blob {
                            Text(Formatting.bytes(entry.size)).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle(path.isEmpty ? repo.name : (path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let ref {
                ToolbarItem(placement: .topBarTrailing) {
                    Label(ref, systemImage: "arrow.triangle.branch")
                        .labelStyle(.titleAndIcon)
                        .font(.footnote)
                        .lineLimit(1)
                }
            }
        }
        .refreshable { await load(force: true) }
        .task(id: "\(path)@\(ref ?? "")") { await load() }
    }

    private func load(force: Bool = false) async {
        await loadState($state) { try await env.repository.directory(repo, path: path, ref: ref, forceRefresh: force) }
    }
}

enum FileIcon {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "ico", "svg"]
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown"]

    static func symbol(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        if imageExtensions.contains(ext) { return "photo" }
        if markdownExtensions.contains(ext) { return "doc.richtext" }
        if ["json", "yml", "yaml", "toml", "xml", "plist"].contains(ext) { return "curlybraces" }
        if ["swift", "kt", "kts", "java", "js", "ts", "tsx", "py", "rb", "go", "rs", "c", "h", "cpp", "m", "sh"].contains(ext) {
            return "chevron.left.forwardslash.chevron.right"
        }
        return "doc.text"
    }
}

/// Code viewer with wrap toggle, font size controls, Markdown preview and image preview.
struct FileScreen: View {
    let repo: RepoRef
    let path: String
    let ref: String?

    @Environment(AppEnvironment.self) private var env
    @State private var state: LoadState<FileContent> = .loading
    @State private var fontSize: CGFloat = 12
    @State private var showsRendered = true

    private var ext: String { (path as NSString).pathExtension.lowercased() }
    private var isMarkdown: Bool { FileIcon.markdownExtensions.contains(ext) }
    private var isImage: Bool { FileIcon.imageExtensions.contains(ext) && ext != "svg" }

    var body: some View {
        Group {
            if isImage {
                ScrollView([.horizontal, .vertical]) {
                    AsyncImage(url: rawURL) { phase in
                        if let image = phase.image { image.resizable().scaledToFit() } else { ProgressView() }
                    }
                    .padding()
                }
            } else {
                AsyncContent(state, retry: { await load(force: true) }) { file in
                    if file.isBinary {
                        ContentUnavailableView("Binary file", systemImage: "doc.zipper",
                                               description: Text("\(Formatting.bytes(file.size)) — open it in the browser to download."))
                    } else if isMarkdown && showsRendered {
                        ScrollView {
                            MarkdownView(markdown: file.content,
                                         context: MarkdownContext(repo: repo, ref: ref ?? "HEAD",
                                                                  directory: (path as NSString).deletingLastPathComponent))
                                .padding()
                        }
                    } else {
                        CodeFileView(content: file.content, wrapLines: env.preferences.codeWrapLines, fontSize: fontSize)
                    }
                }
            }
        }
        .navigationTitle((path as NSString).lastPathComponent)
        .toolbarVisibility(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isImage {
                ToolbarItem(placement: .bottomBar) {
                    Button("Smaller", systemImage: "textformat.size.smaller") { fontSize = max(8, fontSize - 1) }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Larger", systemImage: "textformat.size.larger") { fontSize = min(24, fontSize + 1) }
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Toggle(isOn: Binding(get: { env.preferences.codeWrapLines }, set: { env.preferences.codeWrapLines = $0 })) {
                        Label("Wrap lines", systemImage: "text.word.spacing")
                    }
                }
                if isMarkdown {
                    ToolbarItem(placement: .bottomBar) {
                        Toggle(isOn: $showsRendered) { Label("Preview", systemImage: "eye") }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink(value: Route.commits(repo, ref: ref)) {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                    if let url = state.value.flatMap({ URL(string: $0.htmlURL) }) {
                        ShareLink(item: url)
                        Button("Open in browser", systemImage: "safari") { env.router.openExternally(url) }
                    }
                    if let content = state.value?.content, !content.isEmpty {
                        Button("Copy contents", systemImage: "doc.on.doc") { UIPasteboard.general.string = content }
                    }
                    Button("Copy path", systemImage: "link") { UIPasteboard.general.string = path }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More actions")
            }
        }
        .task(id: "\(path)@\(ref ?? "")") { if !isImage { await load() } }
    }

    private var rawURL: URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "?#;")
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
        return URL(string: "https://raw.githubusercontent.com/\(repo.owner)/\(repo.name)/\(ref ?? "HEAD")/\(encodedPath)")
    }

    private func load(force: Bool = false) async {
        await loadState($state) { try await env.repository.file(repo, path: path, ref: ref, forceRefresh: force) }
    }
}

struct CommitsScreen: View {
    let repo: RepoRef
    let ref: String?

    @Environment(AppEnvironment.self) private var env
    @State private var state: LoadState<[CommitSummary]> = .loading

    var body: some View {
        AsyncContent(state, emptyTitle: "No commits", emptySystemImage: "clock", retry: { await load(force: true) }) { commits in
            List(commits) { commit in
                NavigationLink(value: Route.commit(repo, sha: commit.sha)) {
                    HStack(alignment: .top, spacing: 12) {
                        AvatarView(url: commit.authorAvatarURL, size: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(commit.headline).font(.subheadline.weight(.medium)).lineLimit(2)
                            HStack(spacing: 8) {
                                Text(commit.authorLogin ?? commit.authorName)
                                Text(Formatting.relative(commit.committedAt))
                                Text(commit.shortSHA).monospaced()
                                if commit.isVerified { Image(systemName: "checkmark.seal.fill").foregroundStyle(StateColors.open) }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Commits")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load(force: true) }
        .task(id: ref) { await load() }
    }

    private func load(force: Bool = false) async {
        await loadState($state) { try await env.repository.commits(repo, ref: ref, forceRefresh: force) }
    }
}

struct CommitDetailScreen: View {
    let repo: RepoRef
    let sha: String

    @Environment(AppEnvironment.self) private var env
    @State private var state: LoadState<CommitDetail> = .loading
    @State private var expanded: Set<String> = []

    var body: some View {
        AsyncContent(state, retry: { await load(force: true) }) { detail in
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(detail.summary.headline).font(.headline)
                        if !detail.summary.body.isEmpty {
                            Text(detail.summary.body).font(.subheadline).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            AvatarView(url: detail.summary.authorAvatarURL, size: 20)
                            Text(detail.summary.authorLogin ?? detail.summary.authorName).bold()
                            Text(Formatting.relative(detail.summary.committedAt)).foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                        HStack(spacing: 12) {
                            Text(detail.summary.shortSHA).monospaced()
                            Text("+\(detail.additions)").foregroundStyle(StateColors.added)
                            Text("−\(detail.deletions)").foregroundStyle(StateColors.removed)
                        }
                        .font(.footnote.monospacedDigit())
                    }
                    .textSelection(.enabled)
                }
                Section("Files") {
                    ForEach(detail.files) { file in
                        DisclosureGroup(isExpanded: Binding(
                            get: { expanded.contains(file.id) },
                            set: { if $0 { expanded.insert(file.id) } else { expanded.remove(file.id) } }
                        )) {
                            DiffFileView(file: file, wrapLines: env.preferences.codeWrapLines)
                                .frame(maxHeight: 480)
                                .listRowInsets(EdgeInsets())
                        } label: {
                            FileChangeHeader(file: file)
                        }
                    }
                }
            }
        }
        .navigationTitle(String(sha.prefix(7)))
        .toolbarVisibility(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = state.value.flatMap({ URL(string: $0.htmlURL) }) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Open in browser", systemImage: "safari") { env.router.openExternally(url) }
                }
            }
        }
        .task(id: sha) { await load() }
    }

    private func load(force: Bool = false) async {
        await loadState($state) { try await env.repository.commitDetail(repo, sha: sha, forceRefresh: force) }
    }
}
