import BelayModules
import SwiftUI

/// The screenshot cleaner's settings, shown inside its card.
struct ScreenshotCleanerSettings: View {
    @Bindable var cleaner: ScreenshotCleaner
    var onRemove: () -> Void
    @State private var justSwept = false

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            ModuleRow(title: "Move to Trash after") {
                Picker(selection: $cleaner.rules.age) {
                    ForEach(ScreenshotRules.ages, id: \.self) { age in
                        Text(verbatim: Self.spelled(age)).tag(age)
                    }
                } label: {
                    EmptyView()
                }
                .labelsHidden()
                .fixedSize()
            }

            ModuleRow(title: "Folders") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(cleaner.rules.folders, id: \.self) { path in
                        folderRow(path)
                    }
                    Button("Add Folder…") { addFolder() }
                        .controlSize(.small)
                }
            }

            ModuleRow(title: nil) {
                VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
                    GroupedCheckbox(
                        title: "Keep tagged or edited screenshots",
                        explanation: """
                            Anything you tagged in Finder or saved again after \
                            taking it stays where it is.
                            """,
                        isOn: $cleaner.rules.keepsTouched
                    )
                    GroupedCheckbox(
                        title: "Include screen recordings",
                        isOn: $cleaner.rules.includesRecordings
                    )
                    Text(
                        """
                        Checked every five minutes. Only files macOS marked as \
                        screen captures are touched, whatever they are named. \
                        Screenshots that were already there are counted from \
                        the moment you switch this on.
                        """
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button("Clean Up Now") { sweep() }
                    .controlSize(.small)
                    .disabled(cleaner.rules.folders.isEmpty || !cleaner.isRunning)
                if justSwept {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
                Button("Remove Module", role: .destructive) { onRemove() }
                    .controlSize(.small)
            }
            .padding(.top, 4)
        }
    }

    private func folderRow(_ path: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(verbatim: (path as NSString).abbreviatingWithTildeInPath)
                .font(.system(size: 12))
                .foregroundStyle(cleaner.unreadable.contains(path) ? Color.red : Color.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button {
                cleaner.remove(folder: path)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove Folder"))
        }
    }

    private func addFolder() {
        ModuleFolderPanel.pick(
            message: String(localized: "Choose the folder your screenshots are saved in."),
            startingAt: ScreenshotFolderAccess.systemFolder
        ) { cleaner.add(folder: $0) }
    }

    private func sweep() {
        cleaner.sweep(.requested) {
            withAnimation(.easeOut(duration: 0.2)) { justSwept = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.easeOut(duration: 0.4)) { justSwept = false }
            }
        }
    }

    /// "4 hours", "3 days", in the app's language, by the system's formatter.
    static func spelled(_ age: TimeInterval) -> String {
        Duration.seconds(age).formatted(
            .units(allowed: [.weeks, .days, .hours], width: .wide, maximumUnitCount: 1))
    }
}

/// A settings row inside a card: the pane's label column, narrowed to what a
/// card has room for.
struct ModuleRow<Control: View>: View {
    static var labelWidth: CGFloat { 150 }

    var title: LocalizedStringKey?
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsMetrics.columnGap) {
            label
                .font(.system(size: 12))
                .multilineTextAlignment(.trailing)
                .frame(width: Self.labelWidth, alignment: .trailing)
                .fixedSize(horizontal: false, vertical: true)
            control()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var label: Text {
        guard let title else { return Text(verbatim: "") }
        return Text(title) + Text(verbatim: ":")
    }
}
