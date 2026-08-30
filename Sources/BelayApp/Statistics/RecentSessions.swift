import BelayCore
import SwiftUI

/// The last few finished sessions, under the chart: which agent, which
/// folder, how long, how recently. The aggregate above says Belay earns its
/// keep; this answers the narrower question a person actually returns with —
/// "what ran while I was gone?"
///
/// Reads like the chart's caption row: quiet, secondary, no interaction. The
/// records carry folder names and durations only, the same structural-fields
/// line every detector already holds.
struct RecentSessions: View {
    let records: [SessionRecord]

    /// A glance, not a log; the store keeps a few more for the next cap.
    static let shown = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT SESSIONS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(records.prefix(Self.shown)) { record in
                    row(record)
                }
            }
        }
    }

    private func row(_ record: SessionRecord) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: ProviderMark.image(for: record.provider, size: 12))
                .renderingMode(.template)
                .foregroundStyle(.secondary)
            Text(verbatim: record.workspace ?? Self.name(record.provider))
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 12)
            Text(verbatim: ElapsedTime.compact(record.duration))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(record.endedAt, format: .relative(presentation: .named))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(minWidth: 76, alignment: .trailing)
        }
    }

    /// The row's fallback when a session never named its folder.
    static func name(_ provider: ProviderID) -> String {
        switch provider {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .cline: return "Cline"
        case .copilot: return "Copilot"
        case .generic: return String(localized: "Agent")
        }
    }
}
