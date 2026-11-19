import SwiftUI

struct AvatarView: View {
    let url: String
    var size: CGFloat = 32
    var isOrganization = false

    var body: some View {
        AsyncImage(url: URL(string: sizedURL)) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: isOrganization ? "building.2.crop.circle.fill" : "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(isOrganization ? AnyShape(.rect(cornerRadius: size * 0.22)) : AnyShape(.circle))
        .overlay {
            (isOrganization ? AnyShape(.rect(cornerRadius: size * 0.22)) : AnyShape(.circle))
                .stroke(.separator, lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    /// Asks GitHub's avatar CDN for a size close to what is displayed.
    private var sizedURL: String {
        guard url.contains("avatars.githubusercontent.com") else { return url }
        let px = Int(size * 3)
        return url + (url.contains("?") ? "&" : "?") + "s=\(px)"
    }
}

struct LabelChip: View {
    let label: LabelTag

    var body: some View {
        Text(label.name)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(Color.prefersDarkText(onHex: label.colorHex) ? Color.black : Color.white)
            .background(Color(hex: label.colorHex), in: .capsule)
    }
}

struct FlowChips: View {
    let labels: [LabelTag]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(labels) { LabelChip(label: $0) }
        }
    }
}

/// Wraps children onto multiple lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            width = max(width, x - spacing)
        }
        return (CGSize(width: width, height: y + lineHeight), origins)
    }
}

struct IssueStateIcon: View {
    let kind: IssueOrPullKind
    let state: IssueOrPullState
    var isDraft = false
    /// False inside coloured badges, where the icon takes the surrounding foreground style.
    var tinted = true

    var body: some View {
        if tinted {
            Image(systemName: symbol).foregroundStyle(color)
                .accessibilityLabel(Text(accessibility))
        } else {
            Image(systemName: symbol)
                .accessibilityLabel(Text(accessibility))
        }
    }

    private var symbol: String {
        switch (kind, state) {
        case (.issue, .open): "circle.circle"
        case (.issue, _): "checkmark.circle"
        case (.pullRequest, .merged): "arrow.triangle.merge"
        case (.pullRequest, .closed): "xmark.circle"
        case (.pullRequest, .open): isDraft ? "circle.dashed" : "arrow.triangle.pull"
        }
    }

    private var color: Color {
        if isDraft && state == .open { return StateColors.draft }
        switch state {
        case .open: return StateColors.open
        case .closed: return kind == .issue ? StateColors.merged : StateColors.closed
        case .merged: return StateColors.merged
        }
    }

    private var accessibility: LocalizedStringKey {
        switch state {
        case .open: isDraft ? "Draft" : "Open"
        case .closed: "Closed"
        case .merged: "Merged"
        }
    }
}

/// Solid capsule badge used in detail headers ("Open", "Merged"...).
struct StateBadge: View {
    let kind: IssueOrPullKind
    let state: IssueOrPullState
    var isDraft = false

    var body: some View {
        Label {
            Text(title)
        } icon: {
            IssueStateIcon(kind: kind, state: state, isDraft: isDraft, tinted: false)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color, in: .capsule)
    }

    private var title: LocalizedStringKey {
        switch state {
        case .open: isDraft ? "Draft" : "Open"
        case .closed: "Closed"
        case .merged: "Merged"
        }
    }

    private var color: Color {
        if isDraft && state == .open { return StateColors.draft }
        switch state {
        case .open: return StateColors.open
        case .closed: return kind == .issue ? StateColors.merged : StateColors.closed
        case .merged: return StateColors.merged
        }
    }
}

struct CheckStatusIcon: View {
    let state: String

    var body: some View {
        switch state.uppercased() {
        case "SUCCESS":
            Image(systemName: "checkmark").foregroundStyle(StateColors.open).accessibilityLabel("Checks passed")
        case "FAILURE", "ERROR":
            Image(systemName: "xmark").foregroundStyle(StateColors.closed).accessibilityLabel("Checks failed")
        default:
            Image(systemName: "circle.fill").foregroundStyle(.orange).imageScale(.small).accessibilityLabel("Checks pending")
        }
    }
}

struct LanguageDot: View {
    let name: String
    let colorHex: String?

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Color(hex: colorHex ?? "8C959F")).frame(width: 9, height: 9)
            Text(name)
        }
    }
}

struct StatLabel: View {
    let systemImage: String
    let value: Int

    var body: some View {
        // Tighter than Label's default icon/title gap, which looks detached in caption-sized metadata rows.
        HStack(spacing: 3) {
            Image(systemName: systemImage)
            Text(Formatting.compact(value))
        }
    }
}

/// Row for issue/PR lists.
struct IssueRow: View {
    let item: IssueOrPullSummary
    var showsRepo = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IssueStateIcon(kind: item.kind, state: item.state, isDraft: item.isDraft)
                .font(.body)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                if showsRepo {
                    Text("\(item.repoFullName) #\(String(item.number))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(item.title)
                    .font(.body.weight(.medium))
                    .lineLimit(3)
                if !item.labels.isEmpty {
                    FlowChips(labels: item.labels)
                }
                HStack(spacing: 10) {
                    if !showsRepo { Text("#\(String(item.number))") }
                    Text(Formatting.relative(item.updatedAt))
                    if item.commentCount > 0 {
                        StatLabel(systemImage: "bubble.left", value: item.commentCount)
                    }
                    if let check = item.checkRollup {
                        CheckStatusIcon(state: check.state)
                    }
                    if let decision = item.reviewDecision {
                        ReviewDecisionLabel(decision: decision)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ReviewDecisionLabel: View {
    let decision: String

    var body: some View {
        switch decision {
        case "APPROVED": Label("Approved", systemImage: "checkmark.seal").foregroundStyle(StateColors.open)
        case "CHANGES_REQUESTED": Label("Changes requested", systemImage: "exclamationmark.bubble").foregroundStyle(StateColors.closed)
        case "REVIEW_REQUIRED": Label("Review required", systemImage: "eye")
        default: EmptyView()
        }
    }
}

/// Row for repository lists.
struct RepoRow: View {
    let repo: RepoSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(url: repo.ownerAvatarURL, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(repo.fullName).font(.body.weight(.semibold)).lineLimit(1)
                    if repo.isPrivate { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                    if repo.isArchived { Image(systemName: "archivebox").font(.caption).foregroundStyle(.secondary) }
                }
                if let description = repo.description, !description.isEmpty {
                    Text(description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 12) {
                    if let language = repo.language { LanguageDot(name: language, colorHex: repo.languageColorHex) }
                    StatLabel(systemImage: "star", value: repo.stargazersCount)
                    if repo.forksCount > 0 { StatLabel(systemImage: "tuningfork", value: repo.forksCount) }
                    if !repo.updatedAt.isEmpty { Text(Formatting.relative(repo.updatedAt)) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct UserRow: View {
    let user: UserSummary

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: user.avatarURL, size: 36)
            Text(user.login).font(.body.weight(.medium))
        }
    }
}
