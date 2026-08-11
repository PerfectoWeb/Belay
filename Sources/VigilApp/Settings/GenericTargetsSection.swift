import AppKit
import SwiftUI
import VigilProviders

/// Configuration for the generic provider: which folders and processes count as
/// "an agent is working" for tools Vigil has no first-class support for.
///
/// Presets are data (`GenericPreset.all`), so adding one is an array element in
/// `VigilProviders` and touches nothing here.
struct GenericTargetsSection: View {
    @Binding var targets: [GenericTarget]

    var body: some View {
        SettingsGroup {
            SettingRow(title: "Other tools") {
                Menu("Add a tool…") {
                    ForEach(GenericPreset.all) { preset in
                        Button {
                            add(preset)
                        } label: {
                            Label {
                                Text(preset.displayName)
                            } icon: {
                                Image(presetMark: preset.id)
                            }
                        }
                        // A preset is one tool at one location. Adding Cline
                        // twice does not watch it twice — it watches the same
                        // folder twice and shows the user two identical tiles.
                        // Presets that ask for a folder are the exception: those
                        // are per-project, so Aider in two checkouts is two
                        // legitimate targets.
                        .disabled(isExhausted(preset))
                    }
                }
                .frame(maxWidth: SettingsMetrics.controlWidth, alignment: .leading)
                .accessibilityLabel("Add a tool to watch")
            }

            if targets.isEmpty {
                SettingNote(text: "Nothing configured. Vigil is watching Claude Code only.")
            } else {
                SettingRow {
                    GenericTargetGrid(targets: targets, remove: remove)
                }
            }

            SettingNote(
                text: """
                    A folder changing means work is happening. A process being alive \
                    never counts as work on its own. It only tells Vigil the session \
                    has ended when it disappears.
                    """
            )
        }
    }

    /// True when this preset can add nothing new.
    ///
    /// Fixed-path presets watch one place, so one is all there is. A preset that
    /// prompts for a folder can be added once per folder, and is only exhausted
    /// for folders already on the list.
    func isExhausted(_ preset: GenericPreset) -> Bool {
        guard preset.folderPrompt == nil else { return false }
        return targets.contains { $0.webhookIdentifier == preset.id }
    }

    private func add(_ preset: GenericPreset) {
        guard !isExhausted(preset) else { return }
        guard let prompt = preset.folderPrompt else {
            targets.append(preset.target())
            return
        }
        // The preset cannot know the path — the agent writes wherever you run it.
        guard let folder = pickFolder(prompt: prompt) else { return }
        let watched = preset.target(folder: folder)
        // The same folder chosen twice is the same target, whatever the panel
        // said. Nothing is watched harder for being listed twice.
        guard !targets.contains(where: { $0.watchedFolder == watched.watchedFolder }) else { return }
        targets.append(watched)
    }

    /// Not private: the tiles' remove buttons route through here, and the test
    /// proving the right target goes calls it rather than faking a click.
    func remove(_ target: GenericTarget) {
        targets.removeAll { $0.id == target.id }
    }

    private func pickFolder(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = prompt
        panel.prompt = String(localized: "Watch")
        return panel.runModal() == .OK ? panel.url : nil
    }
}
