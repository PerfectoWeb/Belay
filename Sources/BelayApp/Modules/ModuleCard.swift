import BelayModules
import SwiftUI

/// One module in the list: what it is, whether it is here, and its settings
/// underneath once it is.
struct ModuleCard: View {
    let module: ModuleDescriptor
    var host: ModuleHost
    @State private var hoveringSettings = false

    private var isInstalled: Bool { host.ledger.isInstalled(module.id) }
    private var isEnabled: Bool { host.ledger.isEnabled(module.id) }
    private var isExpanded: Bool { host.browsing.expanded == module.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isInstalled && isExpanded {
                Divider().padding(.vertical, 12)
                settings
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(isInstalled && !isEnabled ? 0.022 : 0.045))
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: module.symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor)
                )
                .opacity(isInstalled && !isEnabled ? 0.4 : 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(module.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if isInstalled {
                    ModuleStatusLine(module: module.id, host: host)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isInstalled { installedControls } else { installButton }
        }
    }

    private var installButton: some View {
        Button("Install") { install() }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
    }

    private var installedControls: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    host.browsing.expanded = isExpanded ? nil : module.id
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isExpanded ? Color.accentColor : Color.primary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isExpanded || hoveringSettings ? 1 : 0.5)
            .animation(.easeOut(duration: 0.18), value: hoveringSettings)
            .onHover { hoveringSettings = $0 }
            .accessibilityLabel(Text("Module settings"))

            MiniSwitch(isOn: isEnabled) { host.setEnabled($0, for: module.id) }
                .accessibilityLabel(Text(module.title))
        }
    }

    @ViewBuilder private var settings: some View {
        switch module.id {
        case .screenshotCleaner:
            ScreenshotCleanerSettings(cleaner: host.screenshots) { host.remove(module.id) }
        case .micKeepWarm:
            MicKeepWarmSettings(keeper: host.microphone) { host.remove(module.id) }
        case .autoAllow:
            AutoAllowSettings(allower: host.autoAllow) { host.remove(module.id) }
        default:
            EmptyView()
        }
    }

    /// Where the build has to ask for the folder, the question comes first and
    /// a cancelled panel installs nothing.
    private func install() {
        guard module.id == .screenshotCleaner, ScreenshotFolderAccess.asksForFolder else {
            host.install(module.id)
            return
        }
        ModuleFolderPanel.pick(
            message: String(localized: "Choose the folder your screenshots are saved in."),
            startingAt: ScreenshotFolderAccess.systemFolder
        ) { folder in
            host.install(module.id, folder: folder)
        }
    }
}
