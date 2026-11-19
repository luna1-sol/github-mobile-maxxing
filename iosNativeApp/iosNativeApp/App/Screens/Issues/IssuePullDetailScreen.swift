import SwiftUI

/// Port of IssuePullDetailPane.kt: header, PR summary, body, timeline, comment composer and PR actions.
struct IssuePullDetailScreen: View {
    let ref: IssueRef

    @Environment(AppEnvironment.self) private var env
    @State private var state: LoadState<IssueOrPullDetail> = .loading
    @State private var draft = ""
    @State private var isPosting = false
    @State private var isMutating = false
    @State private var error: String?
    @State private var showsReview = false
    @State private var showsEditor = false
    @State private var pendingMerge: MergeMethod?
    @State private var editingComment: TimelineEvent.CommentEvent?
    @State private var deletingComment: TimelineEvent.CommentEvent?
    @Namespace private var glassNamespace

    var body: some View {
        AsyncContent(state, retry: { await load(force: true) }) { detail in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    DetailHeader(detail: detail)
                    if detail.isPullRequest { PullSummaryCard(detail: detail) }
                    MetadataCard(detail: detail)
                    CommentCard(
                        author: detail.author, createdAt: detail.createdAt, association: nil,
                        text: detail.body, reactions: detail.reactions,
                        onReact: { content, reacted in await react(subjectID: detail.id, content: content, reacted: reacted) },
                        menu: { bodyMenu(detail) }
                    )
                    ForEach(detail.timeline) { event in
                        TimelineRow(event: event, onReact: react, onEdit: { editingComment = $0 },
                                    onDelete: { deletingComment = $0 }, onQuote: quote)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await load(force: true) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let detail = state.value { bottomBar(detail) }
        }
        .overlay(alignment: .top) {
            if isMutating {
                ProgressView()
                    .padding(12)
                    .glassEffect(.regular, in: .circle)
                    .padding(.top, 8)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.smooth, value: isMutating)
        .navigationTitle("#\(String(ref.number))")
        .toolbarVisibility(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task(id: ref) { await load() }
        .sheet(isPresented: $showsReview) {
            ReviewSheet(ref: ref) { await load(force: true) }
        }
        .sheet(isPresented: $showsEditor) {
            MarkdownEditorSheet(title: "Comment", text: $draft, submitTitle: "Comment") { await postComment() }
        }
        .sheet(item: $editingComment) { comment in
            EditCommentSheet(ref: ref, comment: comment) { await load(force: true) }
        }
        // An alert rather than a confirmation dialog: on iOS 26 the dialog becomes a popover whose arrow points at
        // whatever view it is attached to, not at the comment being deleted.
        .alert("Delete this comment?", isPresented: Binding(get: { deletingComment != nil }, set: { if !$0 { deletingComment = nil } }),
               presenting: deletingComment) { comment in
            Button("Delete", role: .destructive) { Task { await deleteComment(comment) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can't be undone.")
        }
        .errorAlert($error)
    }

    // MARK: Toolbar & bottom bar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if let detail = state.value {
                Menu {
                    if let url = URL(string: detail.htmlURL) {
                        ShareLink(item: url)
                        Button("Open in browser", systemImage: "safari") { env.router.openExternally(url) }
                        Button("Copy link", systemImage: "link") { UIPasteboard.general.url = url }
                    }
                    Button("Go to repository", systemImage: "book.closed") { env.router.push(.repo(ref.repoRef)) }
                    if detail.viewerCanCloseOrReopen && detail.state != .merged {
                        Divider()
                        if detail.state == .open {
                            Button(detail.isPullRequest ? "Close pull request" : "Close issue", systemImage: "xmark.circle", role: .destructive) {
                                Task { await setState(open: false) }
                            }
                        } else {
                            Button(detail.isPullRequest ? "Reopen pull request" : "Reopen issue", systemImage: "arrow.uturn.backward.circle") {
                                Task { await setState(open: true) }
                            }
                        }
                    }
                    if detail.isPullRequest && detail.viewerCanUpdate && detail.state == .open {
                        Button(detail.isDraft ? "Ready for review" : "Convert to draft", systemImage: detail.isDraft ? "eye" : "circle.dashed") {
                            Task { await toggleDraft(detail) }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More actions")
            }
        }
    }

    @ViewBuilder
    private func bottomBar(_ detail: IssueOrPullDetail) -> some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                if detail.isPullRequest && detail.state == .open {
                    HStack(spacing: 10) {
                        Button {
                            env.router.push(.pullFiles(ref))
                        } label: {
                            Label("Files \(detail.changedFilesCount)", systemImage: "doc.text.magnifyingglass")
                        }
                        .buttonStyle(.glass)
                        .glassEffectID("files", in: glassNamespace)
                        Button { showsReview = true } label: {
                            Label("Review", systemImage: "checkmark.bubble")
                        }
                        .buttonStyle(.glass)
                        .glassEffectID("review", in: glassNamespace)
                        if detail.viewerCanMerge && !detail.isDraft {
                            Menu {
                                ForEach(MergeMethod.allCases, id: \.self) { method in
                                    Button(mergeTitle(method)) { pendingMerge = method }
                                }
                            } label: {
                                Label("Merge", systemImage: "arrow.triangle.merge")
                            } primaryAction: {
                                pendingMerge = .squash
                            }
                            .buttonStyle(.glassProminent)
                            .tint(detail.mergeable == "CONFLICTING" ? .gray : StateColors.open)
                            .disabled(isMutating || detail.mergeable == "CONFLICTING")
                            .glassEffectID("merge", in: glassNamespace)
                            .confirmationDialog("Merge this pull request?",
                                                isPresented: Binding(get: { pendingMerge != nil }, set: { if !$0 { pendingMerge = nil } }),
                                                titleVisibility: .visible, presenting: pendingMerge) { method in
                                Button(mergeTitle(method)) { Task { await merge(method) } }
                                Button("Cancel", role: .cancel) {}
                            }
                        }
                    }
                    .controlSize(.regular)
                } else if detail.isPullRequest {
                    Button {
                        env.router.push(.pullFiles(ref))
                    } label: {
                        Label("Files \(detail.changedFilesCount)", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.glass)
                    .glassEffectID("files", in: glassNamespace)
                }
                CommentComposer(draft: $draft, isPosting: isPosting,
                                onExpand: { showsEditor = true },
                                onSend: { Task { await postComment() } })
                    .glassEffectID("composer", in: glassNamespace)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func bodyMenu(_ detail: IssueOrPullDetail) -> some View {
        Button("Copy text", systemImage: "doc.on.doc") { UIPasteboard.general.string = detail.body }
        Button("Quote reply", systemImage: "quote.bubble") { quote(detail.body) }
    }

    private func mergeTitle(_ method: MergeMethod) -> LocalizedStringKey {
        switch method {
        case .squash: "Squash and merge"
        case .merge: "Create a merge commit"
        case .rebase: "Rebase and merge"
        }
    }

    // MARK: Actions

    private func load(force: Bool = false) async {
        await loadState($state) { try await env.repository.issueOrPullDetail(ref, forceRefresh: force) }
    }

    private func quote(_ text: String) {
        let quoted = text.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n")
        draft = (draft.isEmpty ? "" : draft + "\n\n") + quoted + "\n\n"
    }

    private func postComment() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !isPosting else { return }
        isPosting = true
        defer { isPosting = false }
        do {
            try await env.repository.postComment(ref, body: body)
            draft = ""
            await load(force: true)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func react(subjectID: String, content: String, reacted: Bool) async {
        do {
            try await env.repository.toggleReaction(ref, subjectID: subjectID, content: content, currentlyReacted: reacted)
            await load(force: true)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func setState(open: Bool) async {
        await mutate { try await env.repository.setState(ref, open: open) }
    }

    private func toggleDraft(_ detail: IssueOrPullDetail) async {
        await mutate { try await env.repository.setDraft(ref, pullRequestID: detail.id, draft: !detail.isDraft) }
    }

    private func merge(_ method: MergeMethod) async {
        await mutate { try await env.repository.merge(ref, method: method) }
    }

    private func deleteComment(_ comment: TimelineEvent.CommentEvent) async {
        await mutate { try await env.repository.deleteComment(ref, id: comment.id) }
    }

    private func mutate(_ operation: () async throws -> Void) async {
        isMutating = true
        defer { isMutating = false }
        do {
            try await operation()
            await load(force: true)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension TimelineEvent.CommentEvent: Identifiable {}

// MARK: - Header & cards

private struct DetailHeader: View {
    let detail: IssueOrPullDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: Route.repo(RepoRef(owner: detail.repoOwner, name: detail.repoName))) {
                Text("\(detail.repoFullName) #\(String(detail.number))")
                    .font(.subheadline)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            Text(detail.title)
                .font(.title2.bold())
                .textSelection(.enabled)
            HStack(spacing: 10) {
                StateBadge(kind: detail.kind, state: detail.state, isDraft: detail.isDraft)
                NavigationLink(value: Route.user(detail.author.login)) {
                    HStack(spacing: 6) {
                        AvatarView(url: detail.author.avatarURL, size: 20)
                        Text(detail.author.login).bold()
                    }
                }
                .buttonStyle(.plain)
                RelativeTimeText(detail.createdAt).foregroundStyle(.secondary)
            }
            .font(.subheadline)
        }
    }
}

private struct PullSummaryCard: View {
    let detail: IssueOrPullDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let head = detail.headRefName, let base = detail.baseRefName {
                HStack(spacing: 6) {
                    BranchPill(name: base)
                    Image(systemName: "arrow.left").font(.caption).foregroundStyle(.secondary)
                    BranchPill(name: head)
                }
            }
            HStack(spacing: 14) {
                Text("+\(detail.additions)").foregroundStyle(StateColors.added)
                Text("−\(detail.deletions)").foregroundStyle(StateColors.removed)
                Label("\(detail.changedFilesCount)", systemImage: "doc")
                if let check = detail.checkRollup {
                    HStack(spacing: 4) { CheckStatusIcon(state: check.state); Text(checkText(check.state)) }
                }
                if let decision = detail.reviewDecision { ReviewDecisionLabel(decision: decision) }
            }
            .font(.footnote.monospacedDigit())
            if detail.state == .open, let mergeable = detail.mergeable {
                switch mergeable {
                case "CONFLICTING":
                    Label("This branch has conflicts that must be resolved", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(StateColors.closed)
                case "MERGEABLE" where detail.mergeStateStatus == "BLOCKED":
                    Label("Merging is blocked", systemImage: "lock.fill").foregroundStyle(.orange)
                case "MERGEABLE":
                    Label("No conflicts with the base branch", systemImage: "checkmark.circle.fill").foregroundStyle(StateColors.open)
                default:
                    EmptyView()
                }
            }
        }
        .font(.footnote)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 16)
    }

    private func checkText(_ state: String) -> LocalizedStringKey {
        switch state.uppercased() {
        case "SUCCESS": "Checks passed"
        case "FAILURE", "ERROR": "Checks failed"
        default: "Checks pending"
        }
    }
}

struct BranchPill: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption.monospaced())
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.12), in: .capsule)
    }
}

private struct MetadataCard: View {
    let detail: IssueOrPullDetail

    var body: some View {
        if !detail.labels.isEmpty || !detail.assignees.isEmpty || detail.milestone != nil || !detail.requestedReviewers.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if !detail.labels.isEmpty { FlowChips(labels: detail.labels) }
                if !detail.assignees.isEmpty { people("Assignees", detail.assignees) }
                if !detail.requestedReviewers.isEmpty { people("Reviewers", detail.requestedReviewers) }
                if let milestone = detail.milestone {
                    Label(milestone.title, systemImage: "signpost.right").font(.footnote)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentCard(cornerRadius: 16)
        }
    }

    private func people(_ title: LocalizedStringKey, _ users: [UserSummary]) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            ForEach(users) { user in
                NavigationLink(value: Route.user(user.login)) {
                    HStack(spacing: 4) {
                        AvatarView(url: user.avatarURL, size: 20)
                        Text(user.login).font(.footnote)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Timeline

private struct TimelineRow: View {
    let event: TimelineEvent
    let onReact: (String, String, Bool) async -> Void
    let onEdit: (TimelineEvent.CommentEvent) -> Void
    let onDelete: (TimelineEvent.CommentEvent) -> Void
    let onQuote: (String) -> Void

    var body: some View {
        switch event {
        case .comment(let comment):
            CommentCard(
                author: comment.author, createdAt: comment.createdAt, association: comment.authorAssociation,
                text: comment.body, reactions: comment.reactions,
                onReact: { content, reacted in await onReact(comment.id, content, reacted) },
                menu: {
                    Button("Copy text", systemImage: "doc.on.doc") { UIPasteboard.general.string = comment.body }
                    Button("Quote reply", systemImage: "quote.bubble") { onQuote(comment.body) }
                    if comment.viewerCanUpdate {
                        Button("Edit", systemImage: "pencil") { onEdit(comment) }
                    }
                    if comment.viewerCanDelete {
                        Button("Delete", systemImage: "trash", role: .destructive) { onDelete(comment) }
                    }
                }
            )
        case .review(let review):
            VStack(alignment: .leading, spacing: 8) {
                EventLine(symbol: reviewSymbol(review.state), color: reviewColor(review.state), actor: review.author,
                          text: reviewText(review.state), createdAt: review.createdAt)
                if !review.body.isEmpty {
                    MarkdownView(markdown: review.body)
                        .padding(14)
                        .contentCard(cornerRadius: 16)
                }
            }
        case .commit(let commit):
            HStack(spacing: 10) {
                Image(systemName: "smallcircle.filled.circle").foregroundStyle(.secondary).frame(width: 24)
                Text(commit.messageHeadline).font(.footnote).lineLimit(1)
                Spacer()
                Text(commit.oidShort).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        case .stateChange(let change):
            switch change.action {
            case .closed:
                EventLine(symbol: "xmark.circle.fill", color: StateColors.closed, actor: change.actor, text: "closed this", createdAt: change.createdAt)
            case .reopened:
                EventLine(symbol: "arrow.uturn.backward.circle.fill", color: StateColors.open, actor: change.actor, text: "reopened this", createdAt: change.createdAt)
            case .merged(let into):
                EventLine(symbol: "arrow.triangle.merge", color: StateColors.merged, actor: change.actor, text: "merged into \(into)", createdAt: change.createdAt)
            }
        }
    }

    private func reviewSymbol(_ state: String) -> String {
        switch state {
        case "APPROVED": "checkmark.circle.fill"
        case "CHANGES_REQUESTED": "exclamationmark.circle.fill"
        case "DISMISSED": "minus.circle"
        default: "eye.circle"
        }
    }

    private func reviewColor(_ state: String) -> Color {
        switch state {
        case "APPROVED": StateColors.open
        case "CHANGES_REQUESTED": StateColors.closed
        default: .secondary
        }
    }

    private func reviewText(_ state: String) -> LocalizedStringKey {
        switch state {
        case "APPROVED": "approved these changes"
        case "CHANGES_REQUESTED": "requested changes"
        case "DISMISSED": "review dismissed"
        default: "reviewed"
        }
    }
}

private struct EventLine: View {
    let symbol: String
    let color: Color
    let actor: UserSummary?
    let text: LocalizedStringKey
    let createdAt: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 24)
            if let actor {
                AvatarView(url: actor.avatarURL, size: 20)
                Text(actor.login).bold()
            }
            Text(text).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            RelativeTimeText(createdAt).foregroundStyle(.tertiary)
        }
        .font(.footnote)
        .padding(.horizontal, 4)
    }
}

private struct CommentCard<MenuContent: View>: View {
    let author: UserSummary
    let createdAt: String
    let association: String?
    let text: String
    let reactions: [ReactionSummary]
    let onReact: (String, Bool) async -> Void
    @ViewBuilder let menu: () -> MenuContent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                NavigationLink(value: Route.user(author.login)) {
                    HStack(spacing: 8) {
                        AvatarView(url: author.avatarURL, size: 28)
                        Text(author.login).font(.subheadline.bold())
                    }
                }
                .buttonStyle(.plain)
                if let association, association != "NONE" {
                    Text(associationTitle(association))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(Capsule().stroke(.separator))
                }
                RelativeTimeText(createdAt).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu { menu() } label: {
                    Image(systemName: "ellipsis").frame(width: 28, height: 28)
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel("Comment actions")
            }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("No description provided.").italic().foregroundStyle(.secondary)
            } else {
                MarkdownView(markdown: text)
            }
            ReactionBar(reactions: reactions, onReact: onReact)
        }
        .padding(14)
        .contentCard(cornerRadius: 16)
    }
}

private func associationTitle(_ association: String) -> LocalizedStringKey {
    switch association {
    case "OWNER": "Owner"
    case "MEMBER": "Member"
    case "COLLABORATOR": "Collaborator"
    case "CONTRIBUTOR": "Contributor"
    case "FIRST_TIME_CONTRIBUTOR": "First-time contributor"
    case "FIRST_TIMER": "First-timer"
    default: LocalizedStringKey(association.capitalized)
    }
}

private struct ReactionBar: View {
    let reactions: [ReactionSummary]
    let onReact: (String, Bool) async -> Void
    @State private var inFlight: String?

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(reactions) { reaction in
                Button {
                    toggle(reaction.content, reacted: reaction.viewerHasReacted)
                } label: {
                    Text("\(ReactionContent(rawValue: reaction.content)?.emoji ?? "") \(reaction.count)")
                        .font(.footnote.monospacedDigit())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .background(reaction.viewerHasReacted ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1), in: .capsule)
                .overlay(Capsule().stroke(reaction.viewerHasReacted ? Color.accentColor : .clear))
                .disabled(inFlight != nil)
            }
            Menu {
                ForEach(ReactionContent.allCases, id: \.self) { content in
                    let reacted = reactions.first { $0.content == content.rawValue }?.viewerHasReacted ?? false
                    Button("\(content.emoji)\(reacted ? " ✓" : "")") { toggle(content.rawValue, reacted: reacted) }
                }
            } label: {
                Image(systemName: "face.smiling")
                    .font(.footnote)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.1), in: .capsule)
            }
            .accessibilityLabel("Add reaction")
        }
    }

    private func toggle(_ content: String, reacted: Bool) {
        inFlight = content
        Task {
            await onReact(content, reacted)
            inFlight = nil
        }
    }
}

// MARK: - Composer & sheets

private struct CommentComposer: View {
    @Binding var draft: String
    let isPosting: Bool
    let onExpand: () -> Void
    let onSend: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button(action: onExpand) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Open full editor")
            TextField("Leave a comment", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.vertical, 6)
            Button {
                // Close the keyboard: on a short thread there is nothing to scroll to dismiss it.
                focused = false
                onSend()
            } label: {
                Group {
                    if isPosting { ProgressView() } else { Image(systemName: "arrow.up") }
                }
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .disabled(isPosting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send comment")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
    }
}

/// Full-screen Markdown editor with live preview (port of MaxxingFullScreenEditor.kt).
struct MarkdownEditorSheet: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let submitTitle: LocalizedStringKey
    let onSubmit: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var preview = false
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Group {
                if preview {
                    ScrollView {
                        MarkdownView(markdown: text.isEmpty ? String(localized: "Nothing to preview") : text).padding()
                    }
                } else {
                    TextEditor(text: $text)
                        .font(.body.monospaced())
                        .padding(.horizontal)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Picker("Mode", selection: $preview) {
                        Text("Write").tag(false)
                        Text("Preview").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button(submitTitle, systemImage: "arrow.up") {
                            Task {
                                isSubmitting = true
                                await onSubmit()
                                isSubmitting = false
                                if text.isEmpty { dismiss() }
                            }
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }
}

private struct EditCommentSheet: View {
    let ref: IssueRef
    let comment: TimelineEvent.CommentEvent
    let onSaved: () async -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        MarkdownEditorSheet(title: "Edit comment", text: $text, submitTitle: "Save") {
            do {
                try await env.repository.updateComment(ref, id: comment.id, body: text)
                await onSaved()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
        .onAppear { text = comment.body }
        .errorAlert($error)
    }
}

private struct ReviewSheet: View {
    let ref: IssueRef
    let onSubmitted: () async -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var event: ReviewEvent = .comment
    @State private var text = ""
    @State private var isSubmitting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Review", selection: $event) {
                        Label("Comment", systemImage: "bubble.left").tag(ReviewEvent.comment)
                        Label("Approve", systemImage: "checkmark.circle").tag(ReviewEvent.approve)
                        Label("Request changes", systemImage: "exclamationmark.circle").tag(ReviewEvent.requestChanges)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Message") {
                    TextEditor(text: $text).frame(minHeight: 140)
                }
            }
            .navigationTitle("Submit review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Submit", systemImage: "checkmark") { Task { await submit() } }
                            // GitHub requires a body for "comment" and "request changes" reviews.
                            .disabled(event != .approve && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .errorAlert($error)
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await env.repository.submitReview(ref, event: event, body: text)
            await onSubmitted()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - PR files

struct PullFilesScreen: View {
    let ref: IssueRef

    @Environment(AppEnvironment.self) private var env
    @State private var state: LoadState<[PullFileChange]> = .loading
    @State private var expanded: Set<String> = []

    var body: some View {
        AsyncContent(state, emptyTitle: "No changed files", emptySystemImage: "doc", retry: { await load(force: true) }) { files in
            List(files) { file in
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
            .listStyle(.plain)
        }
        .navigationTitle("Files changed")
        .toolbarVisibility(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: Binding(get: { env.preferences.codeWrapLines }, set: { env.preferences.codeWrapLines = $0 })) {
                    Label("Wrap lines", systemImage: "text.word.spacing")
                }
                .toggleStyle(.button)
            }
        }
        .task(id: ref) { await load() }
    }

    private func load(force: Bool = false) async {
        await loadState($state) { try await env.repository.pullFiles(ref, forceRefresh: force) }
    }
}
