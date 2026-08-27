import BelayCore
import SwiftUI

/// One built-in agent, as a tile with a switch. Borderless where the tools
/// below are bordered, so the eye tells at once these come with the app. An
/// agent that is off is not watched, not started, and never asks for a
/// folder; switching it on is the moment Belay may ask.
struct BuiltInProviderTile: View {
    let provider: ProviderStatus
    /// Whether this agent's hooks are installed: the status line says so,
    /// because "precise" versus "inferred" is the one fact about detection
    /// worth a word in the tile.
    var precise = false
    /// Whether the hooks *could* be installed right now: the status line
    /// offers the link, the way a needsSetup tile offers "Fix". The row of
    /// agent names this used to be lived below the tiles and said everything
    /// twice; the tile is the one place about an agent.
    var offersPrecise = false
    var onToggle: (Bool) -> Void = { _ in }
    var onFix: () -> Void = {}
    /// Enable and edit both open the same preview; edit does it on hooks
    /// already in place.
    var onEnablePrecise: () -> Void = {}
    var onEditPrecise: () -> Void = {}
    var onRemovePrecise: () -> Void = {}

    var onAddRoot: () -> Void = {}
    var onRemoveRoot: (String) -> Void = { _ in }
    var onAddSuggested: (String) -> Void = { _ in }
    @State private var hoveringOptions = false
    /// Where the cursor is over the tile, in its own coordinates, for the
    /// spotlight. `nil` when the cursor is elsewhere.
    @State private var cursor: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Centred like the generic tiles' marks, and dimmed rather than
        // recoloured when the agent is off: the logos are pictures, not
        // template glyphs, so opacity is the honest way to grey them.
        HStack(alignment: .center, spacing: 10) {
            Image(nsImage: ProviderMark.image(for: provider.id, size: 20))
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)
                // 0.3 lands on the "Off" line's grey: the tile dims as one.
                .opacity(provider.isEnabled ? 1 : 0.3)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(verbatim: provider.descriptor.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        // Off: the name takes the same grey as its "Off" line.
                        .foregroundStyle(provider.isEnabled ? .primary : .tertiary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    // Their own tight pair: the options button belongs to the
                    // switch, not floating between it and the name.
                    HStack(spacing: 1) {
                        // The tile's right-click menu, one click away.
                        // `.opacity`, not a foreground style: the menu label
                        // repaints its content and ignores the style.
                        Menu {
                            agentMenu
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        // 0.3 lands on the "Off" grey, so a switched-off
                        // tile dims this icon with everything else.
                        .opacity(hoveringOptions ? 1 : (provider.isEnabled ? 0.45 : 0.3))
                        .animation(.easeOut(duration: 0.18), value: hoveringOptions)
                        .onHover { hoveringOptions = $0 }
                        .accessibilityLabel(Text("Options"))
                        // On the name's own line, and small: the switch is a
                        // detail of the row, not a second landmark.
                        MiniSwitch(isOn: provider.isEnabled, toggle: onToggle)
                            .offset(x: 3)
                            .accessibilityLabel(Text(verbatim: provider.descriptor.displayName))
                    }
                }
                status
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The generic tiles' own grey, at two strengths — borderless is the
        // whole difference from the tools below. A blue wash was tried and
        // asked for the eye more than a resting pane should.
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(provider.isEnabled ? 0.045 : 0.022))
        )
        // A soft spotlight riding the cursor. Position tracks raw (no lag);
        // only appearing and fading animate. Reduce Motion brightens evenly.
        // Enabled tiles only: a sleeping tile must not light up.
        .overlay {
            if let cursor, !reduceMotion {
                RadialGradient(
                    colors: [Color.primary.opacity(0.07), .clear],
                    center: .center, startRadius: 0, endRadius: 80
                )
                .frame(width: 160, height: 160)
                .position(cursor)
                .transition(.opacity)
                .allowsHitTesting(false)
            }
            if cursor != nil, reduceMotion {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onContinuousHover { phase in
            switch phase {
            case .active(let location) where provider.isEnabled:
                if cursor == nil {
                    withAnimation(.easeOut(duration: 0.18)) { cursor = location }
                } else {
                    cursor = location
                }
            default:
                if cursor != nil {
                    withAnimation(.easeOut(duration: 0.25)) { cursor = nil }
                }
            }
        }
        // Removal is rare and deliberate, so it lives one click deeper than
        // the offer: the tile's own menu.
        .contextMenu {
            agentMenu
        }
    }

    /// One unit, in the interface's own language: "20 min" in English,
    /// "20 мин" in Russian — `Duration`'s formatter carries the units, so
    /// no catalogue key has to.
    static func activity(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(
            .units(
                allowed: [.hours, .minutes, .seconds],
                width: .abbreviated,
                maximumUnitCount: 1))
    }

    /// Off says off. On says ready (and when it was last heard from), or what
    /// is in the way — one line, never wrapping: the tile is small and a
    /// paragraph with a bordered button in it wore the pane out. The ask is
    /// the path and a Fix link, nothing more.
    @ViewBuilder
    private var status: some View {
        if !provider.isEnabled {
            Text("Off").foregroundStyle(.tertiary)
        } else {
            switch provider.availability {
            case .ready:
                if precise, let last = provider.lastSignal {
                    Text("Precise · last signal \(Self.activity(-last.timeIntervalSinceNow)) ago")
                        .foregroundStyle(.tertiary)
                } else if precise {
                    Text("Precise").foregroundStyle(.tertiary)
                } else if offersPrecise {
                    // The Fix pattern: the fact, then the one action that
                    // changes it, level in the same line.
                    HStack(spacing: 4) {
                        Text("Standard ·").foregroundStyle(.tertiary)
                        Button(action: onEnablePrecise) {
                            Text("Enable Precise…")
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                } else if let last = provider.lastSignal {
                    Text("last signal \(Self.activity(-last.timeIntervalSinceNow)) ago")
                        .foregroundStyle(.tertiary)
                } else if !provider.customRoots.isEmpty {
                    Text("Watching \(provider.customRoots.count + 1) folders")
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Ready").foregroundStyle(.tertiary)
                }
            case .needsSetup:
                HStack(spacing: 5) {
                    Text("Allow access to \(home)")
                        .foregroundStyle(.orange)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Button(action: onFix) {
                        Text("Fix")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    // Level with the switch's right edge, which sits three
                    // points past the content edge from its own trim.
                    .offset(x: 3)
                }
            case .unavailable(let why):
                Text(why).foregroundStyle(.tertiary).truncationMode(.tail)
            }
        }
    }

    /// The folder the ask is about, spelled the way the grant panel shows it.
    var home: String {
        switch provider.id {
        case .codex: return "~/.codex"
        case .cline: return "~/.cline"
        case .copilot: return "~/.copilot"
        default: return "~/.claude"
        }
    }
}
