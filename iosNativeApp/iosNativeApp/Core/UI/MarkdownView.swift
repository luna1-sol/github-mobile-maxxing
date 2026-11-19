import SwiftUI

/// Where relative links and images in a Markdown document point (README files and docs in a repository).
struct MarkdownContext: Hashable {
    var repo: RepoRef
    var ref: String
    /// Directory of the document inside the repository ("" for the root).
    var directory = ""

    func resolveImage(_ raw: String) -> URL? {
        if let url = URL(string: raw), url.scheme != nil { return rewriteBlob(url) }
        let path = resolve(raw)
        return URL(string: "https://raw.githubusercontent.com/\(repo.owner)/\(repo.name)/\(ref)/\(path)")
    }

    func resolveLink(_ raw: String) -> URL? {
        if raw.hasPrefix("#") { return nil }
        if let url = URL(string: raw), url.scheme != nil { return url }
        let path = resolve(raw)
        return URL(string: "https://github.com/\(repo.owner)/\(repo.name)/blob/\(ref)/\(path)")
    }

    private func resolve(_ raw: String) -> String {
        let cleaned = raw.split(separator: "#").first.map(String.init) ?? raw
        var parts: [Substring] = cleaned.hasPrefix("/") ? [] : directory.split(separator: "/")
        for piece in cleaned.split(separator: "/") {
            switch piece {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(piece)
            }
        }
        return parts.joined(separator: "/").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
    }

    /// `github.com/o/r/blob/x.png` shows an HTML page; the raw host serves the image itself.
    private func rewriteBlob(_ url: URL) -> URL {
        guard url.host() == "github.com" else { return url }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count > 4, parts[2] == "blob" || parts[2] == "raw" else { return url }
        let rest = parts.dropFirst(3).joined(separator: "/")
        return URL(string: "https://raw.githubusercontent.com/\(parts[0])/\(parts[1])/\(rest)") ?? url
    }
}

/// Block-level GitHub Flavored Markdown renderer. Inline formatting is delegated to `AttributedString`.
struct MarkdownView: View {
    let markdown: String
    var context: MarkdownContext?

    var body: some View {
        let blocks = MarkdownParser.parse(markdown)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block, context: context)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

enum MarkdownBlock: Hashable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(language: String?, text: String)
    case quote([MarkdownBlock])
    case list(items: [MarkdownListItem])
    case table(header: [String], rows: [[String]])
    case image(url: String, alt: String)
    case rule
}

struct MarkdownListItem: Hashable {
    var marker: String
    var checked: Bool?
    var text: String
    var depth: Int
}

enum MarkdownParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        let normalized = preprocessHTML(source.replacingOccurrences(of: "\r\n", with: "\n"))
        return parseLines(normalized.components(separatedBy: "\n"))
    }

    private static func parseLines(_ lines: [String]) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var i = 0

        func flushParagraph() {
            let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(contentsOf: splitImages(text)) }
            paragraph = []
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph()
                let fence = String(trimmed.prefix(3))
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[i])
                    i += 1
                }
                blocks.append(.code(language: language.isEmpty ? nil : language, text: code.joined(separator: "\n")))
                i += 1
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            // ATX heading
            if let match = trimmed.wholeMatch(of: #/(#{1,6})\s+(.*?)\s*#*/#) {
                flushParagraph()
                blocks.append(.heading(level: match.1.count, text: String(match.2)))
                i += 1
                continue
            }

            // Horizontal rule
            if trimmed.wholeMatch(of: #/([-*_])(\s*\1){2,}/#) != nil {
                flushParagraph()
                blocks.append(.rule)
                i += 1
                continue
            }

            // Setext heading (underline on the next line)
            if !paragraph.isEmpty, trimmed.wholeMatch(of: #/=+|-+/#) != nil {
                let text = paragraph.joined(separator: " ")
                paragraph = []
                blocks.append(.heading(level: trimmed.hasPrefix("=") ? 1 : 2, text: text))
                i += 1
                continue
            }

            // Block quote (also GitHub alerts: > [!NOTE])
            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoted: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    var content = t.dropFirst()
                    if content.hasPrefix(" ") { content = content.dropFirst() }
                    quoted.append(String(content))
                    i += 1
                }
                if let first = quoted.first, let alert = first.wholeMatch(of: #/\[!(\w+)\]/#) {
                    quoted[0] = "**\(alert.1.capitalized)**"
                }
                blocks.append(.quote(parseLines(quoted)))
                continue
            }

            // Table
            if trimmed.hasPrefix("|"), i + 1 < lines.count,
               lines[i + 1].trimmingCharacters(in: .whitespaces).wholeMatch(of: #/\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?/#) != nil {
                flushParagraph()
                let header = tableCells(trimmed)
                var rows: [[String]] = []
                i += 2
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(tableCells(lines[i]))
                    i += 1
                }
                blocks.append(.table(header: header, rows: rows))
                continue
            }

            // Lists
            if listMatch(line) != nil {
                flushParagraph()
                var items: [MarkdownListItem] = []
                while i < lines.count {
                    if let item = listMatch(lines[i]) {
                        items.append(item)
                    } else if !lines[i].trimmingCharacters(in: .whitespaces).isEmpty, lines[i].hasPrefix("  "), !items.isEmpty {
                        items[items.count - 1].text += " " + lines[i].trimmingCharacters(in: .whitespaces)
                    } else {
                        break
                    }
                    i += 1
                }
                blocks.append(.list(items: items))
                continue
            }

            // Indented code (4 spaces) outside a paragraph
            if paragraph.isEmpty, line.hasPrefix("    ") {
                var code: [String] = []
                while i < lines.count, lines[i].hasPrefix("    ") || lines[i].isEmpty {
                    code.append(String(lines[i].dropFirst(min(4, lines[i].count))))
                    i += 1
                }
                while code.last?.isEmpty == true { code.removeLast() }
                blocks.append(.code(language: nil, text: code.joined(separator: "\n")))
                continue
            }

            paragraph.append(line)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    private static func listMatch(_ line: String) -> MarkdownListItem? {
        guard let m = line.wholeMatch(of: #/(\s*)([-*+]|\d{1,9}[.)])\s+(.*)/#) else { return nil }
        var text = String(m.3)
        var checked: Bool?
        if let task = text.wholeMatch(of: #/\[([ xX])\]\s+(.*)/#) {
            checked = task.1 != " "
            text = String(task.2)
        }
        let marker = String(m.2)
        return MarkdownListItem(marker: marker.first?.isNumber == true ? marker : "•", checked: checked,
                                text: text, depth: m.1.count / 2)
    }

    private static func tableCells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Pulls standalone images out of a paragraph so they render as images instead of being dropped.
    private static func splitImages(_ text: String) -> [MarkdownBlock] {
        let pattern = #/!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/#
        guard text.contains("![") else { return [.paragraph(text)] }
        var result: [MarkdownBlock] = []
        var rest = Substring(text)
        while let match = rest.firstMatch(of: pattern) {
            // A linked badge `[![alt](img)](link)` keeps the image; the surrounding link syntax is dropped.
            var before = String(rest[..<match.range.lowerBound])
            if before.hasSuffix("[") { before.removeLast() }
            if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(.paragraph(before)) }
            result.append(.image(url: String(match.2), alt: String(match.1)))
            rest = rest[match.range.upperBound...]
            if let linkTail = rest.prefixMatch(of: #/\]\([^)]*\)/#) { rest = rest[linkTail.range.upperBound...] }
        }
        if !rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(.paragraph(String(rest))) }
        return result
    }

    /// Converts the HTML commonly found in READMEs and issue bodies into Markdown, then drops other tags.
    static func preprocessHTML(_ text: String) -> String {
        var s = text
        s = s.replacing(#/<!--[\s\S]*?-->/#, with: "")
        s = s.replacing(#/(?i)<img\b[^>]*?\bsrc\s*=\s*["']([^"']+)["'][^>]*>/#) { m in
            "\n\n![](\(m.1))\n\n"
        }
        s = s.replacing(#/(?i)<br\s*\/?>/#, with: "  \n")
        s = s.replacing(#/(?i)<a\b[^>]*?\bhref\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/#) { m in
            let label = m.2.trimmingCharacters(in: .whitespacesAndNewlines)
            return label.contains("![") ? label : "[\(label)](\(m.1))"
        }
        s = s.replacing(#/(?i)<summary>([\s\S]*?)<\/summary>/#) { m in "\n\n**\(m.1)**\n\n" }
        s = s.replacing(#/(?i)<\/?(h[1-6])[^>]*>/#) { _ in "\n\n" }
        s = s.replacing(#/(?i)<\/?(p|div|details|picture|source|center|kbd|sub|sup|span|table|tbody|thead|tr|td|th|ul|ol|li|dl|dt|dd)\b[^>]*>/#, with: "")
        return s
    }

    /// Inline Markdown -> `AttributedString`, with @mentions linked to profiles.
    static func inline(_ text: String, context: MarkdownContext?) -> AttributedString {
        let linked = text.replacing(#/(^|[\s(])@([A-Za-z0-9](?:[A-Za-z0-9-]{0,38}))\b/#) { m in
            "\(m.1)[@\(m.2)](https://github.com/\(m.2))"
        }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                              failurePolicy: .returnPartiallyParsedIfPossible)
        // Single newlines inside a paragraph are soft breaks; two trailing spaces are hard breaks.
        let softened = linked
            .replacingOccurrences(of: "  \n", with: "\u{2028}")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
        var attributed = (try? AttributedString(markdown: softened, options: options)) ?? AttributedString(text)
        if let context {
            for run in attributed.runs {
                if let link = run.link, link.scheme == nil, let resolved = context.resolveLink(link.relativeString) {
                    attributed[run.range].link = resolved
                }
            }
        }
        return attributed
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let context: MarkdownContext?

    var body: some View {
        switch block {
        case .heading(let level, let text):
            VStack(alignment: .leading, spacing: 4) {
                Text(MarkdownParser.inline(text, context: context))
                    .font(font(for: level))
                    .padding(.top, level <= 2 ? 6 : 2)
                if level <= 2 { Divider() }
            }
        case .paragraph(let text):
            Text(MarkdownParser.inline(text, context: context))
                .fixedSize(horizontal: false, vertical: true)
        case .code(let language, let text):
            CodeBlockView(code: text, language: language)
        case .quote(let children):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(.quaternary).frame(width: 4)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                        MarkdownBlockView(block: child, context: context)
                    }
                }
                .foregroundStyle(.secondary)
            }
        case .list(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let checked = item.checked {
                            Image(systemName: checked ? "checkmark.square.fill" : "square")
                                .foregroundStyle(checked ? Color.accentColor : .secondary)
                        } else {
                            Text(item.marker).foregroundStyle(.secondary).monospacedDigit()
                        }
                        Text(MarkdownParser.inline(item.text, context: context))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.depth) * 16)
                }
            }
        case .table(let header, let rows):
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                            Text(MarkdownParser.inline(cell, context: context)).bold()
                        }
                    }
                    Divider()
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(MarkdownParser.inline(cell, context: context))
                            }
                        }
                    }
                }
                .padding(12)
            }
            .contentCard(cornerRadius: 12)
        case .image(let raw, let alt):
            let url = context?.resolveImage(raw) ?? URL(string: raw)
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit().frame(maxWidth: .infinity, alignment: .leading)
                case .failure:
                    Label(alt.isEmpty ? String(localized: "Image") : alt, systemImage: "photo")
                        .font(.caption).foregroundStyle(.secondary)
                default:
                    ProgressView().frame(height: 40)
                }
            }
            .accessibilityLabel(alt)
        case .rule:
            Divider()
        }
    }

    private func font(for level: Int) -> Font {
        switch level {
        case 1: .title.bold()
        case 2: .title2.bold()
        case 3: .title3.bold()
        default: .headline
        }
    }
}
