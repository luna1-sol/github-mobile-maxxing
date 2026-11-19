import Foundation

/// Parses a unified diff patch (as returned in GitHub's `patch` field) into hunks. Port of DiffParser.kt.
enum DiffParser {
    static func parse(_ patch: String?) -> [DiffHunk] {
        guard let patch, !patch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var hunks: [DiffHunk] = []
        var header: String?
        var oldStart = 0, oldCount = 0, newStart = 0, newCount = 0
        var oldLine = 0, newLine = 0
        var lines: [DiffLine] = []

        func flush() {
            guard let header else { return }
            hunks.append(DiffHunk(header: header, oldStart: oldStart, oldCount: oldCount,
                                  newStart: newStart, newCount: newCount, lines: lines))
            lines = []
        }

        for raw in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw.hasSuffix("\r") ? raw.dropLast() : raw)
            if let h = parseHunkHeader(line) {
                flush()
                header = line
                (oldStart, oldCount, newStart, newCount) = h
                oldLine = oldStart
                newLine = newStart
                continue
            }
            guard header != nil else { continue }
            if line.hasPrefix("+") {
                lines.append(DiffLine(kind: .added, content: String(line.dropFirst()), oldLineNumber: nil, newLineNumber: newLine))
                newLine += 1
            } else if line.hasPrefix("-") {
                lines.append(DiffLine(kind: .removed, content: String(line.dropFirst()), oldLineNumber: oldLine, newLineNumber: nil))
                oldLine += 1
            } else if line.hasPrefix("\\") {
                lines.append(DiffLine(kind: .meta, content: line, oldLineNumber: nil, newLineNumber: nil))
            } else {
                let content = line.hasPrefix(" ") ? String(line.dropFirst()) : line
                lines.append(DiffLine(kind: .context, content: content, oldLineNumber: oldLine, newLineNumber: newLine))
                oldLine += 1
                newLine += 1
            }
        }
        flush()
        return hunks
    }

    /// `@@ -a[,b] +c[,d] @@ ...` -> (a, b, c, d); a missing count means 1.
    static func parseHunkHeader(_ line: String) -> (Int, Int, Int, Int)? {
        guard let match = line.wholeMatch(of: #/@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)/#) else { return nil }
        guard let a = Int(match.1), let c = Int(match.3) else { return nil }
        let b = match.2.flatMap { Int($0) } ?? 1
        let d = match.4.flatMap { Int($0) } ?? 1
        return (a, b, c, d)
    }
}
