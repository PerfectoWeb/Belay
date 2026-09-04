import BelayCore
import SwiftUI

/// The Sessions side of the statistics switcher: a real table, not a widget.
///
/// `Table` because this is exactly what AppKit tables are for — click a
/// header to sort, click again to flip, click a row to select it, double-click
/// to open — and SwiftUI's wraps the native one, so the free behaviour is the
/// correct behaviour. Newest first by default: the question someone opens this
/// with is "what just ran?", not "what ran longest?", and the second click
/// answers the second question.
///
/// Columns stop at what Belay actually measures: per-process load would mean
/// sampling every session all day to decorate a table, an answer other apps
/// already sell that is not worth the wakeups.
struct SessionsScreen: View {
    let records: [SessionRecord]
    /// Inside a folder the column would repeat the headline.
    var hidesFolder = false
    /// A double-click or Return on a row; nil where there is nowhere to go.
    var onOpen: ((SessionRecord) -> Void)?

    @State private var order = [KeyPathComparator(\SessionRecord.endedAt, order: .reverse)]
    @State private var selection: SessionRecord.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if records.isEmpty {
                empty
            } else if hidesFolder {
                // Two tables rather than one conditional column: a column
                // behind an `if` needs macOS 14.4 and the floor is 14.0.
                decorated(
                    Table(rows, selection: $selection, sortOrder: $order) {
                        agent
                        duration
                        tokens
                        finished
                    })
            } else {
                decorated(
                    Table(rows, selection: $selection, sortOrder: $order) {
                        agent
                        folder
                        duration
                        tokens
                        finished
                    })
                Text("last \(SessionHistoryStore.capacity) sessions, folder names only")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 5)
                    .padding(.leading, 5)
            }
        }
    }

    private var rows: [SessionRecord] { records.sorted(using: order) }

    /// The native table's own gestures: a double-click on a row is the
    /// primary action, the empty menu keeps a right-click from offering a menu
    /// of nothing, and Return opens the selection the way Finder does.
    private func decorated(_ table: some View) -> some View {
        table
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: SessionRecord.ID.self) { _ in
            } primaryAction: { ids in
                open(ids.first)
            }
            .onKeyPress(.return) {
                open(selection)
                return .handled
            }
            // Fills whatever the window gives it, exactly: the columns'
            // budget stays under the pane width and the height stops at the
            // pane's edge, so the one scroller on this screen is the table's
            // own, vertical, and only when the rows earn it.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func open(_ id: SessionRecord.ID?) {
        guard let onOpen, let record = records.first(where: { $0.id == id }),
            record.workspace != nil
        else { return }
        onOpen(record)
    }

    private var agent: TableColumn<SessionRecord, KeyPathComparator<SessionRecord>, some View, Text> {
        TableColumn(Text("Agent"), value: \.agentName) { record in
            HStack(spacing: 6) {
                Image(nsImage: ProviderMark.image(for: record.provider, size: 12))
                    .renderingMode(.template)
                    .foregroundStyle(.secondary)
                Text(verbatim: record.agentName)
            }
        }
        .width(min: 110, ideal: 120, max: 140)
    }

    private var folder: TableColumn<SessionRecord, KeyPathComparator<SessionRecord>, some View, Text> {
        TableColumn(Text("Folder"), value: \.folder) { record in
            Text(verbatim: record.folder)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .width(min: 110, ideal: 140, max: 200)
    }

    private var duration: TableColumn<SessionRecord, KeyPathComparator<SessionRecord>, some View, Text> {
        TableColumn(Text("Duration"), value: \.duration) { record in
            Text(verbatim: ElapsedTime.compact(record.duration))
                .monospacedDigit()
        }
        .width(min: 60, ideal: 72, max: 80)
    }

    private var tokens: TableColumn<SessionRecord, KeyPathComparator<SessionRecord>, some View, Text> {
        TableColumn(Text("Tokens"), value: \.tokensSort) { record in
            Text(verbatim: record.tokensLabel)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .width(min: 56, ideal: 68, max: 84)
    }

    private var finished: TableColumn<SessionRecord, KeyPathComparator<SessionRecord>, some View, Text> {
        TableColumn(Text("Finished"), value: \.endedAt) { record in
            Self.finished(record.endedAt)
                .foregroundStyle(.secondary)
        }
        .width(min: 100, ideal: 110, max: 130)
    }

    /// "11 hours ago" while recency still means something; a plain date once
    /// it does not. Three days is where "4 days ago" stops being easier to
    /// read than "27 Aug".
    static func finished(_ date: Date, now: Date = Date()) -> Text {
        if now.timeIntervalSince(date) < 3 * 86_400 {
            return Text(date, format: .relative(presentation: .named))
        }
        return Text(date, format: .dateTime.day().month(.abbreviated))
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
