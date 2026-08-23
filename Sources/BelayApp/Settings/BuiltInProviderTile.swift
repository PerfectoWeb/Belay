import BelayCore
import SwiftUI

/// One of the two agents Belay understands natively, as a tile with a switch.
///
/// The switch is the whole story of this tile. An agent that is off is not
/// watched, not started, and never asks for a folder; switching it on is the
/// moment Belay may ask, because the person just said they want it watched.
/// The first tester without Codex was told to "allow access to ~/.codex" by
/// a build that could not tell "not granted" from "not there" — hence the
/// switch, and hence the line under the name, which now says *which*.
struct BuiltInProviderTile: View {
    let provider: ProviderStatus
    var onToggle: (Bool) -> Void = { _ in }
    var onFix: () -> Void = {}
    /// Non-nil for the agent whose hooks Belay can install.
    var precise: PreciseDetection?
    var onEnablePrecise: () -> Void = {}
    var onRemovePrecise: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: ProviderMark.image(for: provider.id, size: 26))
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
                .foregroundStyle(provider.isEnabled ? .primary : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: provider.descriptor.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(provider.isEnabled ? .primary : .secondary)
                status
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Toggle(isOn: Binding(get: { provider.isEnabled }, set: onToggle)) {
                    EmptyView()
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel(Text(verbatim: provider.descriptor.displayName))
                control
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor))
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

    @ViewBuilder
    private var control: some View {
        if provider.isEnabled {
            switch provider.availability {
            case .needsSetup:
                Button("Fix", action: onFix)
                    .controlSize(.small)
            case .unavailable:
                EmptyView()
            case .ready:
                if let precise, provider.descriptor.supportsPreciseDetection, PreciseDetection.isSupported {
                    // The mark alone: blue when the hooks are in, grey when
                    // not, and the menu says which in words.
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
                }
            }
        }
    }
}
