import BelayModules
import SwiftUI

extension OrphanAgent {
    /// The agent as the Agents pane names it.
    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }
}

/// One process in the orphan watch's list: its name, its pid, where it came
/// from, and what can be done about it. Never a path and never arguments.
struct OrphanRow: View {
    let name: String
    let pid: pid_t
    let detail: Text
    /// Nil in the App Store build, where the sandbox lets no signal out.
    var onEnd: (() -> Void)?
    var onIgnore: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(verbatim: name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(verbatim: "\(pid)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                detail
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let onEnd {
                Button("End", action: onEnd).controlSize(.small)
            }
            Button("Ignore", action: onIgnore).controlSize(.small)
        }
    }
}

extension OrphanWatchSettings {
    @ViewBuilder var leftBehindList: some View {
        let items = watcher.findings.leftBehind
        if items.isEmpty {
            Text("Nothing left behind")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                TimelineView(.everyMinute) { context in
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(items) { item in
                            OrphanRow(
                                name: item.name, pid: item.pid,
                                detail: Text(
                                    """
                                    From \(item.agent.displayName), running for \
                                    \(age(item.startedAt, context.date))
                                    """),
                                onEnd: endAction(item.pid, item.name, item.startedAt),
                                onIgnore: { watcher.ignore(item.name) })
                        }
                    }
                }
                footer(count: items.count)
            }
        }
    }

    @ViewBuilder var hotList: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 8) {
                ForEach(watcher.findings.hot) { item in
                    OrphanRow(
                        name: item.name, pid: item.pid,
                        detail: Text(
                            """
                            Averaging \(item.percent)% of a core while \
                            \(item.agent.displayName) is idle, running for \
                            \(age(item.startedAt, context.date))
                            """),
                        onEnd: endAction(item.pid, item.name, item.startedAt),
                        onIgnore: { watcher.ignore(item.name) })
                }
            }
        }
    }

    @ViewBuilder var ignoredList: some View {
        if watcher.rules.ignored.isEmpty {
            Text("None. Press Ignore on a row to leave a name out.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(watcher.rules.ignored, id: \.self) { name in
                    HStack(spacing: 6) {
                        Text(verbatim: name).font(.system(size: 12))
                        Button {
                            watcher.unignore(name)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Stop Ignoring"))
                    }
                }
            }
        }
    }

    func age(_ started: Date, _ now: Date) -> String {
        ElapsedTime.compact(now.timeIntervalSince(started))
    }
}
