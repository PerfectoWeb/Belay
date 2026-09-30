import BelayModules
import SwiftUI

/// The warm microphone's settings, shown inside its card.
struct MicKeepWarmSettings: View {
    @Bindable var keeper: MicKeepWarm
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            ModuleRow(title: nil) {
                VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
                    GroupedCheckbox(
                        title: "Pause on battery power",
                        explanation: """
                            The microphone is let go while the Mac runs on its \
                            battery and picked up again on power.
                            """,
                        isOn: $keeper.rules.pausesOnBattery
                    )
                    GroupedCheckbox(
                        title: "Leave Bluetooth headphones alone",
                        explanation: """
                            A Bluetooth microphone, such as AirPods, is not \
                            held. Holding it keeps the headphones in call mode, \
                            which lowers the quality of what you listen to.
                            """,
                        isOn: $keeper.rules.leavesBluetoothAlone
                    )
                    Text(
                        """
                        While the microphone is held, macOS shows the orange \
                        microphone dot. Belay listens to nothing: the sound is \
                        thrown away as it arrives, never recorded, stored or \
                        sent.
                        """
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                if keeper.warmth == .needsPermission {
                    Button("Open Microphone Settings") { MicSurroundings.openSettings() }
                        .controlSize(.small)
                }
                Spacer(minLength: 0)
                Button("Remove Module", role: .destructive) { onRemove() }
                    .controlSize(.small)
            }
            .padding(.top, 4)
        }
    }
}
