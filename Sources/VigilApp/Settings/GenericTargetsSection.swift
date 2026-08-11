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
            withAnimation(TargetTileMetrics.arrival) { targets.append(preset.target()) }
            return
        }
        // The preset cannot know the path — the agent writes wherever you run it.
        pickFolder(prompt: prompt) { adopt(preset, folder: $0) }
    }

    /// Not private: the test for the folder-prompt path calls this instead of
    /// driving a real open panel, which no test can do.
    func adopt(_ preset: GenericPreset, folder: URL) {
        let watched = preset.target(folder: folder)
        // The same folder chosen twice is the same target, whatever the panel
        // said. Nothing is watched harder for being listed twice.
        guard !targets.contains(where: { $0.watchedFolder == watched.watchedFolder }) else { return }
        withAnimation(TargetTileMetrics.arrival) { targets.append(watched) }
    }

    /// Not private: the tiles' remove buttons route through here, and the test
    /// proving the right target goes calls it rather than faking a click.
    func remove(_ target: GenericTarget) {
        withAnimation(TargetTileMetrics.departure) { targets.removeAll { $0.id == target.id } }
    }

    /// A sheet on the Settings window, never `runModal()`.
    ///
    /// This is reached from a `Menu` action, so a modal session would be nested
    /// inside `NSMenu`'s own tracking loop: the main run loop stops for as long
    /// as the user browses, which freezes the panel and leaves the menu bar icon
    /// showing whatever state it was last drawn in — it can say "working" while
    /// nothing is. The same nesting is a known way to get a picker that opens
    /// unresponsive or behind its window, and in the sandboxed build the call is
    /// a synchronous round trip to the open-and-save panel service, which on a
    /// cold launch is a hard freeze rather than a stutter.
    private func pickFolder(prompt: String, then adopt: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = prompt
        panel.prompt = String(localized: "Watch")

        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            adopt(url)
        }
        // Every window-presenting path in this app activates first; without it
        // the sheet arrives behind whatever the user was looking at.
        NSApp.activate(ignoringOtherApps: true)
        guard let window = Self.hostWindow else {
            // No Settings window means no sheet to hang, which should not happen
            // — but dropping the user's click silently would be worse.
            panel.begin(completionHandler: finish)
            return
        }
        panel.beginSheetModal(for: window, completionHandler: finish)
    }

    /// The window this section is hosted in. A SwiftUI view has no route to its
    /// own `NSWindow`, and `SettingsWindow` already stamps an identifier for
    /// exactly this kind of lookup.
    static var hostWindow: NSWindow? {
        NSApp.windows.first { $0.identifier == SettingsWindow.windowIdentifier }
    }
}
