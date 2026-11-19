import Foundation
import SwiftUI

enum Formatting {
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(_ iso8601: String) -> Date? {
        guard !iso8601.isEmpty else { return nil }
        return iso.date(from: iso8601) ?? isoFractional.date(from: iso8601)
    }

    /// "3 hours ago" in the user's language; empty for unparsable input.
    static func relative(_ iso8601: String, now: Date = .now) -> String {
        guard let date = date(iso8601) else { return "" }
        return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }

    static func shortDate(_ iso8601: String) -> String {
        guard let date = date(iso8601) else { return iso8601 }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    /// 1234 -> "1.2K", like GitHub's counters.
    static func compact(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

/// Relative timestamp ("3 min. ago") that stays current. A plain `Text(Formatting.relative(...))` freezes at its first
/// render: after a reload SwiftUI skips rows whose inputs did not change, so a just-created event kept saying "2 sec. ago".
struct RelativeTimeText: View {
    let iso8601: String

    init(_ iso8601: String) {
        self.iso8601 = iso8601
    }

    var body: some View {
        TimelineView(.everyMinute) { _ in
            Text(Formatting.relative(iso8601))
        }
    }
}
