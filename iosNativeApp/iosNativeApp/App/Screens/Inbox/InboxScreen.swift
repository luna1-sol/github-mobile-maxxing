import SwiftUI

/// Port of NotificationsScreen.kt: filtered inbox with swipe-to-done / mark-read triage.
struct InboxScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var state: LoadState<[NotificationThread]> = .loading
    @State private var error: String?
    @State private var isSwitching = false

    var body: some View {
        let filter = env.preferences.inboxFilter
        AsyncContent(state, emptyTitle: filter == .unread ? "Inbox zero" : "No notifications",
                     emptySystemImage: "tray", retry: { await load() }, isRefreshing: isSwitching) { threads in
            List {
                ForEach(threads) { thread in
                    Button { open(thread) } label: { NotificationRow(thread: thread) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button { Task { await markDone(thread) } } label: {
                                Label("Done", systemImage: "checkmark")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if thread.unread {
                                Button { Task { await markRead(thread) } } label: {
                                    Label("Mark as read", systemImage: "envelope.open")
                                }
                                .tint(.blue)
                            }
                        }
                        .contextMenu {
                            if thread.unread {
                                Button("Mark as read", systemImage: "envelope.open") { Task { await markRead(thread) } }
                            }
                            Button("Done", systemImage: "checkmark") { Task { await markDone(thread) } }
                            Button("Open repository", systemImage: "book.closed") {
                                env.router.push(.repo(RepoRef(owner: thread.repoOwner, name: thread.repoName)))
                            }
                            Button("Open in browser", systemImage: "safari") { env.router.openExternally(thread.htmlFallbackURL) }
                        }
                }
            }
            .listStyle(.plain)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            FilterChips(selection: Binding(get: { env.preferences.inboxFilter }, set: { env.preferences.inboxFilter = $0 }),
                        options: InboxFilter.allCases) { option in
                switch option {
                case .unread: "Unread"
                case .participating: "Participating"
                case .all: "All"
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle("Inbox")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Mark all as read", systemImage: "checkmark.circle") { Task { await markAllRead() } }
                    .disabled(!(state.value?.contains(where: \.unread) ?? false))
            }
        }
        .refreshable { await load() }
        .task(id: filter) {
            guard state.value != nil else { return await load() }
            isSwitching = true
            defer { isSwitching = false }
            await load(replacing: true)
        }
        .errorAlert($error)
    }

    private func load(replacing: Bool = false) async {
        let filter = env.preferences.inboxFilter
        let operation = { try await env.repository.notifications(filter: filter) }
        if replacing { await replaceState($state, operation) } else { await loadState($state, operation) }
        if filter == .unread, let threads = state.value { env.unreadCount = threads.filter(\.unread).count }
    }

    private func open(_ thread: NotificationThread) {
        if let ref = thread.issueRef {
            env.router.push(.issue(ref))
        } else {
            env.router.openExternally(thread.htmlFallbackURL)
        }
        if thread.unread { Task { await markRead(thread) } }
    }

    private func markRead(_ thread: NotificationThread) async {
        update(thread.id) { $0.unread = false }
        do {
            try await env.repository.markNotificationRead(thread.id)
            env.unreadCount = max(0, env.unreadCount - 1)
        } catch {
            update(thread.id) { $0.unread = true }
            self.error = error.localizedDescription
        }
    }

    private func markDone(_ thread: NotificationThread) async {
        guard var threads = state.value, let index = threads.firstIndex(where: { $0.id == thread.id }) else { return }
        withAnimation { _ = threads.remove(at: index); state = .loaded(threads) }
        do {
            try await env.repository.markNotificationDone(thread.id)
            if thread.unread { env.unreadCount = max(0, env.unreadCount - 1) }
        } catch {
            if var current = state.value {
                current.insert(thread, at: min(index, current.count))
                state = .loaded(current)
            }
            self.error = error.localizedDescription
        }
    }

    private func markAllRead() async {
        do {
            try await env.repository.markAllNotificationsRead()
            env.unreadCount = 0
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func update(_ id: String, _ change: (inout NotificationThread) -> Void) {
        guard var threads = state.value, let index = threads.firstIndex(where: { $0.id == id }) else { return }
        change(&threads[index])
        // A read thread stays in the Unread list until the next refresh so rows don't jump under the finger.
        state = .loaded(threads)
    }
}

private struct NotificationRow: View {
    let thread: NotificationThread

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .topLeading) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(thread.unread ? Color.accentColor : .secondary)
                    .frame(width: 28)
                if thread.unread {
                    Circle().fill(Color.accentColor).frame(width: 8, height: 8).offset(x: -6, y: -2)
                        .accessibilityLabel("Unread")
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(thread.repoFullName + (thread.subjectNumber.map { " #\($0)" } ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text(Formatting.relative(thread.updatedAt)).font(.caption).foregroundStyle(.tertiary)
                }
                Text(thread.subjectTitle)
                    .font(.body.weight(thread.unread ? .semibold : .regular))
                    .lineLimit(3)
                Text(reasonText)
                    .font(.caption)
                    .foregroundStyle(thread.reason.isUrgent ? Color.orange : .secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }

    private var symbol: String {
        switch thread.subjectType {
        case .issue: "circle.circle"
        case .pullRequest: "arrow.triangle.pull"
        case .commit: "smallcircle.filled.circle"
        case .release: "tag"
        case .discussion: "bubble.left.and.bubble.right"
        case .checkSuite: "checkmark.seal"
        case .unknown: "bell"
        }
    }

    private var reasonText: LocalizedStringKey {
        switch thread.reason {
        case .assign: "Assigned"
        case .author: "Author"
        case .comment: "Comment"
        case .ciActivity: "CI activity"
        case .invitation: "Invitation"
        case .manual: "Subscribed manually"
        case .mention: "Mentioned"
        case .reviewRequested: "Review requested"
        case .securityAlert: "Security alert"
        case .stateChange: "State changed"
        case .subscribed: "Watching"
        case .teamMention: "Team mentioned"
        case .other: "Notification"
        }
    }
}

/// Horizontally scrolling Liquid Glass filter chips; the selected chip morphs between positions.
struct FilterChips<Option: Hashable & Sendable>: View {
    @Binding var selection: Option
    let options: [Option]
    let title: (Option) -> LocalizedStringKey
    @Namespace private var namespace

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        let selected = option == selection
                        Button {
                            withAnimation(.smooth) { selection = option }
                        } label: {
                            Text(title(option))
                                .font(.subheadline.weight(selected ? .semibold : .regular))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(selected ? Color.white : .primary)
                        .glassEffect(selected ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
                        .glassEffectID(option, in: namespace)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
        .scrollClipDisabled()
    }
}
