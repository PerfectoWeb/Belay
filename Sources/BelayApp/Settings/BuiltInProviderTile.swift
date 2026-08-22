import BelayCore
import SwiftUI

/// One of the two agents Belay understands natively, drawn as a tile in the
/// same grid language as the tools the user adds below — mark, name, one
/// line of state — so the pane reads as one list of watched agents with the
/// built-in ones first, rather than a form above a grid.
///
/// What differs from a generic tile is the line under the name and the
/// control on the right: the line says whether the agent is ready, needs a
/// grant, or is not there, and the control is the one thing a person can do
/// about it — `Fix` when access is missing, the precise-detection menu on
/// the agent that has one.
struct BuiltInProviderTile: View {
    let provider: ProviderStatus
    /// Non-nil for the agent whose hooks Belay can install.
    var precise: PreciseDetection?
    var onEnablePrecise: () -> Void = {}
    var onRemovePrecise: () -> Void = {}
    var onFix: () -> Void = {}

    var body: some View {
        HStack(spacing: 9) {
            Image(nsImage: ProviderMark.image(for: provider.id, size: TargetTileMetrics.markSize))
                .resizable()
                .interpolation(.high)
                .frame(width: TargetTileMetrics.markSize, height: TargetTileMetrics.markSize)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: provider.descriptor.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                status
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 6)

            control
        }
        .padding(TargetTileMetrics.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: TargetTileMetrics.corner)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: TargetTileMetrics.corner)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
        .accessibilityElement(children: .combine)
    }

    /// Ready agents say when they were last heard from, which is the health
    /// line risk R1 asks for; the others say what is wrong.
    @ViewBuilder
    private var status: some View {
        switch provider.availability {
        case .ready:
            if let last = provider.lastSignal {
                Text("last signal \(ElapsedTime.compact(-last.timeIntervalSinceNow)) ago")
                    .foregroundStyle(.tertiary)
            } else {
                Text("Ready")
                    .foregroundStyle(.tertiary)
            }
        case .needsSetup(let what):
            Text(what)
                .foregroundStyle(.orange)
        case .unavailable(let why):
            Text(why)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var control: some View {
        switch provider.availability {
        case .needsSetup:
            Button("Fix", action: onFix)
                .controlSize(.small)
        case .unavailable:
            EmptyView()
        case .ready:
            if let precise, provider.descriptor.supportsPreciseDetection, PreciseDetection.isSupported {
                // The mark alone: the menu's label ignores the tile's font,
                // and the words squeezed the agent's own name to "Cl…". Blue
                // when the hooks are in, grey when they are not, and the
                // menu says which in words.
                Menu {
                    if precise.isInstalled {
                        Button("Remove", action: onRemovePrecise)
                    } else {
                        Button("Enable…", action: onEnablePrecise)
                    }
                } label: {
                    Image(systemName: "scope")
                        .foregroundStyle(precise.isInstalled ? Color.accentColor : Color.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(precise.isInstalled ? "Precise detection is on" : "Precise detection is off")
                .accessibilityLabel("Precise detection")
            }
        }
    }
}
