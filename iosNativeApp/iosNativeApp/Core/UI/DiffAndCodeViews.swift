import SwiftUI

// Port of core/ui DiffAndCodeViewers.kt: fenced code blocks, a line-numbered file viewer and a unified diff viewer.

/// Lightweight keyword/string/comment highlighter. Good enough for reading code on a phone without a parser.
enum SyntaxHighlighter {
    private static let keywords: Set<String> = [
        "func", "let", "var", "if", "else", "for", "while", "return", "import", "class", "struct", "enum", "protocol",
        "extension", "switch", "case", "default", "break", "continue", "guard", "in", "is", "as", "try", "catch",
        "throw", "throws", "async", "await", "public", "private", "internal", "fileprivate", "static", "final",
        "override", "init", "self", "super", "nil", "true", "false", "null", "fun", "val", "object", "interface",
        "package", "data", "sealed", "when", "const", "function", "def", "lambda", "from", "export", "new", "this",
        "typeof", "void", "int", "long", "float", "double", "bool", "boolean", "string", "char", "fn", "impl", "pub",
        "mut", "use", "mod", "match", "type", "where", "yield", "with", "pass", "None", "True", "False", "and", "or",
        "not", "elif", "except", "finally", "raise", "go", "chan", "defer", "select", "map", "range", "do", "end",
    ]

    static func highlight(_ line: String) -> AttributedString {
        var result = AttributedString()
        var index = line.startIndex
        var word = ""

        func flushWord() {
            guard !word.isEmpty else { return }
            var part = AttributedString(word)
            if keywords.contains(word) {
                part.foregroundColor = .pink
            } else if word.first?.isNumber == true {
                part.foregroundColor = .orange
            } else if word.first?.isUppercase == true {
                part.foregroundColor = .teal
            }
            result += part
            word = ""
        }

        while index < line.endIndex {
            let char = line[index]
            let rest = line[index...]
            if rest.hasPrefix("//") || char == "#" && (rest.count == 1 || rest.dropFirst().first == " ") {
                flushWord()
                var comment = AttributedString(String(rest))
                comment.foregroundColor = .secondary
                result += comment
                return result
            }
            if char == "\"" || char == "'" || char == "`" {
                flushWord()
                var end = line.index(after: index)
                while end < line.endIndex, line[end] != char {
                    if line[end] == "\\" { end = line.index(end, offsetBy: 2, limitedBy: line.endIndex) ?? line.endIndex } else { end = line.index(after: end) }
                }
                let stop = end < line.endIndex ? line.index(after: end) : line.endIndex
                var literal = AttributedString(String(line[index..<stop]))
                literal.foregroundColor = .green
                result += literal
                index = stop
                continue
            }
            if char.isLetter || char.isNumber || char == "_" {
                word.append(char)
            } else {
                flushWord()
                result += AttributedString(String(char))
            }
            index = line.index(after: index)
        }
        flushWord()
        return result
    }
}

/// Fenced code block inside Markdown.
struct CodeBlockView: View {
    let code: String
    var language: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code.split(separator: "\n", omittingEmptySubsequences: false)
                .map { SyntaxHighlighter.highlight(String($0)) }
                .reduce(into: AttributedString()) { acc, line in
                    if !acc.characters.isEmpty { acc += AttributedString("\n") }
                    acc += line
                })
                .font(.system(.footnote, design: .monospaced))
                .padding(12)
        }
        .contentCard(cornerRadius: 12)
        .overlay(alignment: .topTrailing) {
            Button {
                UIPasteboard.general.string = code
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.glass)
            .controlSize(.mini)
            .padding(6)
            .accessibilityLabel("Copy code")
        }
    }
}

/// Full file viewer with line numbers and optional wrapping.
struct CodeFileView: View {
    let content: String
    var wrapLines: Bool
    var fontSize: CGFloat = 12

    var body: some View {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let digits = String(lines.count).count
        let rows = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .top, spacing: 12) {
                    Text(String(index + 1))
                        .foregroundStyle(.tertiary)
                        .frame(minWidth: CGFloat(digits) * fontSize * 0.62, alignment: .trailing)
                    Text(SyntaxHighlighter.highlight(line))
                        .fixedSize(horizontal: !wrapLines, vertical: true)
                        .frame(maxWidth: wrapLines ? .infinity : nil, alignment: .leading)
                }
                .font(.system(size: fontSize, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 1)
            }
        }
        .textSelection(.enabled)
        .padding(.vertical, 8)

        if wrapLines {
            ScrollView { rows }
        } else {
            // A 2D scroll view centers content smaller than itself; code reads from the top-left corner.
            ScrollView([.vertical, .horizontal]) { rows }
                .defaultScrollAnchor(.topLeading)
        }
    }
}

/// Unified diff for one changed file.
struct DiffFileView: View {
    let file: PullFileChange
    var wrapLines = false
    var fontSize: CGFloat = 11

    var body: some View {
        if file.hunks.isEmpty {
            Text(file.patch == nil ? "Binary file or diff too large to display." : "No changes to display.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding()
        } else {
            // Without wrapping, every line is padded to the longest one (the font is monospaced) so the
            // added/removed background bands line up; infinite-width frames can't be used inside a 2D scroll view.
            let width = wrapLines ? 0 : file.hunks.flatMap(\.lines).map(\.content.count)
                .reduce(file.hunks.map(\.header.count).max() ?? 0, max)
            ScrollView(wrapLines ? .vertical : [.vertical, .horizontal]) {
                // One flat list with unique ids: nested ForEach(id: \.offset) gave every hunk's lines the same ids,
                // and LazyVStack then skipped the rows of later hunks, leaving blank gaps.
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Self.rows(file.hunks)) { row in
                        switch row.content {
                        case .header(let header):
                            Text(wrapLines ? header : Self.padded(header, to: width + 16))
                                .font(.system(size: fontSize, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .frame(maxWidth: wrapLines ? .infinity : nil, alignment: .leading)
                                .background(Color.accentColor.opacity(0.08))
                        case .line(let line):
                            DiffLineRow(line: line, wrapLines: wrapLines, fontSize: fontSize, padTo: width)
                        }
                    }
                }
                .textSelection(.enabled)
            }
            .defaultScrollAnchor(.topLeading)
        }
    }
}

extension DiffFileView {
    struct Row: Identifiable {
        enum Content {
            case header(String)
            case line(DiffLine)
        }

        let id: Int
        let content: Content
    }

    /// Hunk headers and lines in display order, numbered so each row has its own identity.
    static func rows(_ hunks: [DiffHunk]) -> [Row] {
        var rows: [Row] = []
        for hunk in hunks {
            rows.append(Row(id: rows.count, content: .header(hunk.header)))
            for line in hunk.lines {
                rows.append(Row(id: rows.count, content: .line(line)))
            }
        }
        return rows
    }

    static func padded(_ text: String, to width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }
}

private struct DiffLineRow: View {
    let line: DiffLine
    let wrapLines: Bool
    let fontSize: CGFloat
    var padTo = 0

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(line.oldLineNumber.map(String.init) ?? "").frame(width: fontSize * 3, alignment: .trailing)
            Text(line.newLineNumber.map(String.init) ?? "").frame(width: fontSize * 3, alignment: .trailing)
            Text(prefix).frame(width: fontSize * 0.8)
            Text(wrapLines ? (line.content.isEmpty ? " " : line.content) : DiffFileView.padded(line.content, to: max(padTo, 1)))
                .fixedSize(horizontal: !wrapLines, vertical: true)
                .frame(maxWidth: wrapLines ? .infinity : nil, alignment: .leading)
        }
        .font(.system(size: fontSize, design: .monospaced))
        .foregroundStyle(line.kind == .meta ? Color.secondary : Color.primary)
        .padding(.vertical, 1)
        .padding(.trailing, 8)
        .frame(maxWidth: wrapLines ? .infinity : nil, alignment: .leading)
        .background(background)
    }

    private var prefix: String {
        switch line.kind {
        case .added: "+"
        case .removed: "-"
        default: " "
        }
    }

    private var background: Color {
        switch line.kind {
        case .added: StateColors.added.opacity(0.15)
        case .removed: StateColors.removed.opacity(0.15)
        default: .clear
        }
    }
}

struct FileChangeHeader: View {
    let file: PullFileChange

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.filename).font(.subheadline.monospaced()).lineLimit(2).truncationMode(.head)
                if let previous = file.previousFilename, previous != file.filename {
                    Text("from \(previous)").font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text("+\(file.additions)").foregroundStyle(StateColors.added)
            Text("−\(file.deletions)").foregroundStyle(StateColors.removed)
        }
        .font(.caption.monospacedDigit())
    }

    private var symbol: String {
        switch file.status {
        case .added: "plus.square"
        case .removed: "minus.square"
        case .renamed, .copied: "arrow.right.square"
        default: "square.and.pencil"
        }
    }

    private var color: Color {
        switch file.status {
        case .added: StateColors.added
        case .removed: StateColors.removed
        default: .orange
        }
    }
}
