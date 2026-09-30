import BelayModules
import SwiftUI

/// The one line under an installed module's summary: off, a problem, or what
/// it has done.
struct ModuleStatusLine: View {
    let module: ModuleID
    var host: ModuleHost

    var body: some View {
        line
            .font(.system(size: 10))
            .lineLimit(1)
    }

    @ViewBuilder private var line: some View {
        if !host.ledger.isEnabled(module) {
            Text("Off").foregroundStyle(.tertiary)
        } else {
            switch module {
            case .screenshotCleaner: screenshots
            case .micKeepWarm: microphone
            case .autoAllow: autoAllow
            default: EmptyView()
            }
        }
    }

    @ViewBuilder private var screenshots: some View {
        if let lost = host.screenshots.unreadable.first {
            let name = URL(fileURLWithPath: lost).lastPathComponent
            Text("Belay cannot read \(name). Choose the folder again.")
                .foregroundStyle(.red)
        } else {
            Text("Moved to the Trash so far: \(host.screenshots.trashedTotal)")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var microphone: some View {
        switch host.microphone.warmth {
        case .warm:
            Text("Keeping \(host.microphone.microphone ?? "") ready")
                .foregroundStyle(.secondary)
        case .pausedOnBattery:
            Text("Paused on battery power").foregroundStyle(.secondary)
        case .pausedForBluetooth:
            Text("Paused for a Bluetooth microphone").foregroundStyle(.secondary)
        case .needsPermission:
            Text("Belay has no access to the microphone.").foregroundStyle(.red)
        case .noMicrophone:
            Text("No microphone found.").foregroundStyle(.secondary)
        case .off:
            Text(verbatim: " ")
        }
    }

    @ViewBuilder private var autoAllow: some View {
        if host.autoAllow.standing == .agentOff {
            Text("\(AutoAllower.agentName) is switched off in Agents.")
                .foregroundStyle(.secondary)
        } else if host.autoAllow.standing == .needsAccess {
            Text("Belay needs Accessibility access to press the button.")
                .foregroundStyle(.red)
        } else {
            Text("Approved so far: \(host.autoAllow.log.total)")
                .foregroundStyle(.secondary)
        }
    }
}
