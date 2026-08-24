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

            VStack(alignment: .leading, spacing: 2) {
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
                HStack(alignment: .top, spacing: 6) {
                    status
                        .font(.system(size: 10))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if provider.isEnabled, case .needsSetup = provider.availability {
                        Button("Fix", action: onFix)
                            .controlSize(.small)
                    }
                }
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

    /// The compact elapsed form, with whole minutes written out: the copy
    /// pass asked for "20 min", and only the lone-minutes shape changes —
    /// seconds and mixed hours keep the compact spelling.
    static func activity(_ seconds: TimeInterval) -> String {
        let compact = ElapsedTime.compact(seconds)
        guard !compact.contains("h"), compact.hasSuffix("m") else { return compact }
        return compact.dropLast() + " min"
    }

    /// Off says off. On says ready (and when it was last heard from), or what
    /// is in the way — "not installed" is a fact, in grey; "needs the folder"
    /// is a request, in orange, and only ever for an agent that is on.
    @ViewBuilder
    private var status: some View {
        if !provider.isEnabled {
            Text("Off").foregroundStyle(.tertiary)
        } else {
            switch provider.availability {
            case .ready:
                if let last = provider.lastSignal {
                    Text("last signal \(Self.activity(-last.timeIntervalSinceNow)) ago")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Ready").foregroundStyle(.secondary)
                }
            case .needsSetup(let what):
                Text(what).foregroundStyle(.orange)
            case .unavailable(let why):
                Text(why).foregroundStyle(.tertiary)
            }
        }
    }
}
