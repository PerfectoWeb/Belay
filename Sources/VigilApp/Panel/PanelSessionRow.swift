import SwiftUI
import VigilCore

/// One agent session: provider glyph, workspace, what it is doing, how long.
///
/// The elapsed column is the only thing in the panel that changes on its own,
/// so it is the only thing wrapped in a `TimelineView`. Ticking the whole row —
/// or worse, a `Timer` on the window — is what docs/08 names as the fastest way
/// to blow the idle CPU budget.
struct PanelSessionRow: View {
    let session: SessionRow
    /// Whether the session's subagents are showing.
    var isExpanded = false
    /// Non-nil only when there are subagents to disclose.
    var onToggle: (() -> Void)?

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if let onToggle {
            Button(action: onToggle) { row }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: 8) {
            // The vendor's own mark, as a template image. Recognising the tool
            // at 15 pt is the whole job of this column, and no invented shape
            // does that as well as the logo the user already knows.
            Image(providerMark: session.provider, preset: session.kind)
                .resizable()
                .frame(width: 15, height: 15)
                .foregroundStyle(glyphStyle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.workspace)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 3) {
                    subtitle
                        .font(.system(size: 10))
                        .foregroundStyle(contrast == .increased ? .primary : .secondary)
                        .lineLimit(1)
                    if onToggle != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
            }

            Spacer(minLength: 4)

            TimelineView(.periodic(from: session.since, by: 1)) { context in
                Text(ElapsedTime.compact(context.date.timeIntervalSince(session.since)))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(contrast == .increased ? .primary : .secondary)
            }
            .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The state, plus how many agents are working under it. The count is what
    /// makes an otherwise quiet-looking session explain why the Mac is awake.
    private var subtitle: Text {
        guard !session.children.isEmpty else { return Text(session.rollup.panelLabel) }
        // Whole sentences, not two halves glued together: a translator handed
        // " · %lld agents" on its own has no way to agree it with what precedes
        // it, and several languages need to.
        let state = String(localized: session.rollup.panelLabel)
        let count = session.children.count
        return Text(
            count == 1
                ? String(localized: "\(state) · 1 agent")
                : String(localized: "\(state) · \(count) agents"))
    }

    private var glyphStyle: AnyShapeStyle {
        session.rollup.isLive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
    }

    /// Read as one sentence; the ticking value is deliberately snapshotted here
    /// rather than live, so VoiceOver is not re-announcing the row every second.
    private var accessibilityLabel: Text {
        let elapsed = ElapsedTime.spoken(Date().timeIntervalSince(session.since))
        let state = String(localized: session.rollup.panelLabel)
        return Text("\(session.workspace), \(state), for \(elapsed)")
    }
}

/// A subagent, under the session that spawned it. Deliberately quieter than a
/// session row: these are not things the user started, and there can be dozens.
struct PanelSubagentRow: View {
    let session: SessionRow
    /// Passed in so one timeline can drive the whole block.
    let now: Date

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(session.activity.isLive ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)

            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(session.activity.isLive ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            Text(session.activity.panelLabel)
                .font(.system(size: 10))
                .foregroundStyle(contrast == .increased ? .primary : .tertiary)
                .lineLimit(1)

            Text(ElapsedTime.compact(now.timeIntervalSince(session.since)))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(contrast == .increased ? .primary : .tertiary)
                .frame(minWidth: 26, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(name), \(String(localized: session.activity.panelLabel))"))
    }

    /// The agent's configured type, which is what distinguishes one row from
    /// the next. Never its task description — that is a summary of the user's
    /// prompt, and the panel is on screen during screen shares.
    private var name: String {
        session.kind ?? String(localized: "Subagent")
    }
}

extension SessionActivity {
    /// A `LocalizedStringResource` rather than a `LocalizedStringKey`: the panel
    /// needs it as a `Text`, and the row that counts agents needs the same word
    /// as a `String` to build one sentence out of. Only the former can do both.
    var panelLabel: LocalizedStringResource {
        switch self {
        case .working: return "Working"
        case .awaitingUser: return "Waiting for you"
        case .idle: return "Idle"
        case .ended: return "Finished"
        }
    }

    var isLive: Bool {
        switch self {
        case .working, .awaitingUser: return true
        case .idle, .ended: return false
        }
    }
}
