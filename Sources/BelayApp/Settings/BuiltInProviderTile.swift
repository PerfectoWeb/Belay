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
        HStack(spacing: 10) {
            Image(nsImage: ProviderMark.image(for: provider.id, size: 24))
                .resizable()
                .interpolation(.high)
                .frame(width: 24, height: 24)
                .foregroundStyle(provider.isEnabled ? .primary : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: provider.descriptor.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(provider.isEnabled ? .primary : .secondary)
                    .lineLimit(1)
                status
                    .font(.system(size: 11))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 6) {
                Toggle(isOn: Binding(get: { provider.isEnabled }, set: onToggle)) {
                    EmptyView()
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel(Text(verbatim: provider.descriptor.displayName))
                if provider.isEnabled, case .needsSetup = provider.availability {
                    Button("Fix", action: onFix)
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(provider.isEnabled ? 0.10 : 0.05))
        )
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
                    Text("last signal \(ElapsedTime.compact(-last.timeIntervalSinceNow)) ago")
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
