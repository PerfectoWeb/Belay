import BelayCore
import SwiftUI

/// The Sessions side of the statistics switcher: a real table, not a widget.
///
/// `Table` because this is exactly what AppKit tables are for — click a
/// header to sort, click again to flip — and SwiftUI's wraps the native one,
/// so the free behaviour is the correct behaviour. Newest first by default:
/// the question someone opens this with is "what just ran?", not "what ran
/// longest?", and the second click answers the second question.
///
/// Columns stop at what Belay actually measures. Tokens and cost would mean
/// reading transcript fields the privacy policy promises to leave alone, and
/// per-process load would mean sampling every session all day to decorate a
/// table — both are answers other apps already sell, neither is worth the
/// promise or the wakeups.
struct SessionsScreen: View {
    let records: [SessionRecord]

    @State private var order = [KeyPathComparator(\SessionRecord.endedAt, order: .reverse)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if records.isEmpty {
                empty
            } else {
                Table(records.sorted(using: order), sortOrder: $order) {
                    TableColumn(Text("Agent"), value: \.agentName) { record in
                        HStack(spacing: 6) {
                            Image(nsImage: ProviderMark.image(for: record.provider, size: 12))
                                .renderingMode(.template)
                                .foregroundStyle(.secondary)
                            Text(verbatim: record.agentName)
                        }
                    }
                    .width(min: 120, ideal: 130, max: 150)
                    TableColumn(Text("Folder"), value: \.folder) { record in
                        Text(verbatim: record.folder)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .width(min: 120, ideal: 180)
                    TableColumn(Text("Duration"), value: \.duration) { record in
                        Text(verbatim: ElapsedTime.compact(record.duration))
                            .monospacedDigit()
                    }
                    .width(min: 64, ideal: 76, max: 96)
                    TableColumn(Text("Tokens"), value: \.tokensSort) { record in
                        Text(verbatim: record.tokensLabel)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 60, ideal: 72, max: 90)
                    TableColumn(Text("Finished"), value: \.endedAt) { record in
                        Text(record.endedAt, format: .relative(presentation: .named))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 104, ideal: 120, max: 140)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                // Fills whatever the window gives it, exactly: the columns'
                // budget stays under the pane width and the height stops at
                // the pane's edge, so the one scroller on this screen is the
                // table's own, vertical, and only when the rows earn it.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// The screen exists before its first finished session does; say so
    /// rather than showing an empty grid.
    private var empty: some View {
        VStack(spacing: 6) {
            Text("No finished sessions yet")
                .font(.system(size: 13, weight: .semibold))
            Text("A session appears here once it ends, if it ran for at least a minute.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
