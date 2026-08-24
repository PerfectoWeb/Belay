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
    var onToggle: (Bool) -> Void = { _ in }
    var onFix: () -> Void = {}

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
                    // On the name's own line, and small: the switch is a
                    // detail of the row, not a second landmark.
                    Toggle(isOn: Binding(get: { provider.isEnabled }, set: onToggle)) {
                        EmptyView()
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    // Below mini there is nothing to ask AppKit for, so the
                    // last step down is drawn: 85%, hugging the right edge.
                    .scaleEffect(0.85, anchor: .trailing)
                    .offset(x: 3)
                    .labelsHidden()
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
                if let last = provider.lastSignal {
                    Text("last signal \(Self.activity(-last.timeIntervalSinceNow)) ago")
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
        provider.id == .codex ? "~/.codex" : "~/.claude"
    }
}
