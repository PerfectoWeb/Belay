import BelayCore
import SwiftUI

/// One of the two agents Belay understands natively, as a tile with a switch.
///
/// Tinted and borderless, where the tools the user adds below are bordered
/// and grey: the eye should tell at once that these two come with the app.
/// The switch is the whole story of the tile. An agent that is off is not
/// watched, not started, and never asks for a folder; switching it on is
/// the moment Belay may ask, because the person just said they want it
/// watched.
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
    var onEnablePrecise: () -> Void = {}
    var onRemovePrecise: () -> Void = {}
    var onAddRoot: () -> Void = {}
    var onRemoveRoot: (String) -> Void = { _ in }
    @State private var hoveringOptions = false

    var body: some View {
        // Centred like the generic tiles' marks, and dimmed rather than
        // recoloured when the agent is off: the logos are pictures, not
        // template glyphs, so opacity is the honest way to grey them.
        HStack(alignment: .center, spacing: 10) {
            Image(nsImage: ProviderMark.image(for: provider.id, size: 20))
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)
                .opacity(provider.isEnabled ? 1 : 0.35)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(verbatim: provider.descriptor.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(provider.isEnabled ? .primary : .secondary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    // The same menu the tile answers right-click with, one
                    // click away for whoever never right-clicks a tile.
                    Menu {
                        agentMenu
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(hoveringOptions ? 0.95 : 0.4))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .onHover { hoveringOptions = $0 }
                    .accessibilityLabel(Text("Options"))
                    // On the name's own line, and small: the switch is a
                    // detail of the row, not a second landmark.
                    MiniSwitch(isOn: provider.isEnabled, toggle: onToggle)
                        .offset(x: 3)
                        .accessibilityLabel(Text(verbatim: provider.descriptor.displayName))
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
        // Removal is rare and deliberate, so it lives one click deeper than
        // the offer: the tile's own menu.
        .contextMenu {
            agentMenu
        }
    }

    /// One menu, three entrances: the slider button, right-click, Control-click.
    @ViewBuilder
    private var agentMenu: some View {
        if precise {
            Button {
                onRemovePrecise()
            } label: {
                Label("Remove Precise Detection", systemImage: "bolt.slash")
            }
        } else if offersPrecise {
            Button {
                onEnablePrecise()
            } label: {
                Label("Enable Precise Detection…", systemImage: "bolt")
            }
        }
        Menu {
            // The default home rides along for context; only the added
            // folders are removable, and removal is the click itself.
            Button {
            } label: {
                Label(home, systemImage: "house")
            }
            .disabled(true)
            if !provider.customRoots.isEmpty {
                Text("Click a folder to stop watching it")
                ForEach(provider.customRoots, id: \.self) { path in
                    Button {
                        onRemoveRoot(path)
                    } label: {
                        Label(
                            (path as NSString).abbreviatingWithTildeInPath,
                            systemImage: "folder")
                    }
                }
            }
            Divider()
            Button {
                onAddRoot()
            } label: {
                Label("Add Folder…", systemImage: "folder.badge.plus")
            }
        } label: {
            Label("Watched Folders", systemImage: "folder")
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
    private var home: String {
        switch provider.id {
        case .codex: return "~/.codex"
        case .cline: return "~/.cline"
        case .copilot: return "~/.copilot"
        default: return "~/.claude"
        }
    }
}

/// A switch drawn in SwiftUI instead of hosted from AppKit.
///
/// `NSSwitch` animates its knob into place when it is created already on,
/// and a Settings window busy with its first layout freezes that entrance:
/// a solid blue capsule with no knob for a second or two, on every open of
/// this pane. Two rounds of animation-suppression did not cure it, because
/// the slide belongs to AppKit, not to SwiftUI. A drawn switch has no
/// entrance to freeze — the first frame is the true state — and the only
/// thing that ever animates is a real click.
struct MiniSwitch: View {
    let isOn: Bool
    let toggle: (Bool) -> Void

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule(style: .circular)
                .fill(isOn ? Color.accentColor : Color.primary.opacity(0.18))
            Circle()
                .fill(.white)
                .shadow(color: .black.opacity(0.25), radius: 0.7, y: 0.5)
                .padding(1)
        }
        .frame(width: 22, height: 13)
        .animation(.easeOut(duration: 0.16), value: isOn)
        .contentShape(Rectangle())
        .onTapGesture { toggle(!isOn) }
        .accessibilityRepresentation {
            Toggle(isOn: Binding(get: { isOn }, set: toggle)) { EmptyView() }
        }
    }
}
