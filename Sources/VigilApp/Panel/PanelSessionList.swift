import SwiftUI
import VigilCore

/// The active-sessions block.
///
/// Five rows by default, because a menu bar panel that grows without bound
/// stops being a menu bar panel (docs/05) — but "+N more" is a button, not a
/// dead label, and opens the full list in a scroller. Hiding work Vigil is
/// holding the Mac awake for, with no way to see it, was the wrong trade.
struct PanelSessionList: View {
    static let visibleLimit = 5
    /// Roughly six rows. Past this the list scrolls rather than pushing the
    /// footer off the bottom of the screen.
    static let scrollerHeight: CGFloat = 208

    let sessions: [SessionRow]

    @State private var showingAll = false
    @State private var expanded: Set<SessionID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header

            if sessions.isEmpty {
                Text("No active sessions.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            } else if showingAll {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 4) { rows(sessions) }
                        .padding(.trailing, 4)
                }
                .frame(maxHeight: Self.scrollerHeight)
                .scrollBounceBehavior(.basedOnSize)
                disclosure(title: "Show fewer", symbol: "chevron.up", isCollapse: true) {
                    showingAll = false
                }
            } else {
                rows(Array(sessions.prefix(Self.visibleLimit)))
                if overflow > 0 {
                    disclosure(
                        title: "\(overflow) more", symbol: "chevron.down", isCollapse: false
                    ) {
                        showingAll = true
                    }
                }
            }
        }
        .onChange(of: sessions.map(\.id)) { _, ids in
            // A session that ended takes its expansion with it, so reappearing
            // ids do not come back pre-opened.
            expanded.formIntersection(Set(ids))
            if overflow == 0 { showingAll = false }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Active sessions")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if total > sessions.count {
                // The subagent count is otherwise invisible while every parent
                // is collapsed, and it is the number that explains the hold.
                Text(total, format: .number)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("\(total) sessions in total, including subagents")
            }
        }
    }

    @ViewBuilder private func rows(_ sessions: [SessionRow]) -> some View {
        ForEach(sessions) { session in
            PanelSessionRow(
                session: session,
                isExpanded: expanded.contains(session.id),
                onToggle: session.children.isEmpty ? nil : { toggle(session.id) }
            )
            if expanded.contains(session.id) {
                PanelSubagentList(children: session.children)
            }
        }
    }

    private func disclosure(
        title: LocalizedStringResource,
        symbol: String,
        isCollapse: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 8, weight: .semibold))
                Text(title).font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
            .padding(.leading, 24)
            .padding(.vertical, 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCollapse ? Text("Show fewer sessions") : Text("Show all sessions"))
    }

    private func toggle(_ id: SessionID) {
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }

    private var overflow: Int {
        max(0, sessions.count - Self.visibleLimit)
    }

    /// Sessions and subagents together.
    private var total: Int {
        sessions.reduce(0) { $0 + 1 + $1.children.count }
    }
}

/// A session's subagents, indented under it. Scrolls on its own once a workflow
/// gets big — fifty-four agents must not push everything else off the panel.
private struct PanelSubagentList: View {
    let children: [SessionRow]

    static let inlineLimit = 4
    static let scrollerHeight: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if children.count > Self.inlineLimit {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) { rows }
                }
                .frame(height: Self.scrollerHeight)
                .scrollBounceBehavior(.basedOnSize)
            } else {
                rows
            }
        }
        .padding(.leading, 23)
        .overlay(alignment: .leading) {
            // A hairline rather than a box: the rows are already indented, and
            // this only has to say "these belong to the row above".
            Rectangle()
                .fill(.quaternary)
                .frame(width: 1)
                .padding(.leading, 7)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(children.count) subagents")
    }

    /// One timeline for the whole block. Fifty-four rows each waking on their
    /// own one-second timer is exactly what docs/08 budgets against, and a
    /// subagent's age does not need second precision.
    @ViewBuilder private var rows: some View {
        TimelineView(.periodic(from: children.first?.since ?? .now, by: 5)) { context in
            VStack(alignment: .leading, spacing: 0) {
                ForEach(children) { child in
                    PanelSubagentRow(session: child, now: context.date)
                }
            }
        }
    }
}
