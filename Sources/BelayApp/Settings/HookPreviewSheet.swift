import BelayCore
import SwiftUI

/// Shows exactly what will be written to the agent's settings file, before
/// anything is written.
///
/// This sheet *is* the consent required by `docs/00-INVARIANTS.md` invariant 6. If the file
/// cannot be edited safely, it degrades to showing a snippet to copy rather than
/// refusing with no way forward — the user's agent config is theirs, and being
/// told "no" with no alternative is worse than being handed the text.
struct HookPreviewSheet: View {
    var precise: PreciseDetection
    var provider: ProviderID = .claudeCode
    var onFinish: () -> Void
    @Environment(\.dismiss) private var dismiss
    /// True while the codex install runs: writing the file is instant, but
    /// recording the approval spawns `codex app-server` and takes a moment.
    @State private var installing = false

    private var isCodex: Bool { provider == .codex }
    private var isCline: Bool { provider == .cline }
    private var path: String {
        switch provider {
        case .codex: return precise.codexHooksPath
        case .cline: return precise.clineHooksPath
        default: return precise.settingsPath
        }
    }

    /// What the sheet shows as "will be written": Cline's is one script that
    /// lands under six event names, the other two are the merged JSON.
    private var proposed: String? {
        switch provider {
        case .codex: return precise.codexPreview()?.proposed
        case .cline: return precise.clinePreview()
        default: return precise.preview()?.proposed
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The agent's own mark, so whose settings these are is clear
            // before a word is read.
            HStack(spacing: 8) {
                Image(nsImage: ProviderMark.image(for: provider, size: 20))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
                Text("Enable precise detection")
                    .font(.title3).bold()
            }

            if let preview = proposed {
                // Why anyone would want this, before the machinery: the diff
                // below reads scary on its own, and the point of the feature
                // deserves the first sentence.
                Text(
                    """
                    With precise detection, \(agentName) tells Belay the exact moment \
                    work starts, stops, or waits for you. Detection becomes instant \
                    and reliable.
                    """
                )
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

                Text("Belay will change \(path) to:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                codeBlock(preview)
                Text(
                    """
                    A timestamped backup is made first. Everything already in the \
                    file is preserved, and "Remove" puts it back exactly.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if isCodex {
                    Text(
                        """
                        Belay also records these hooks as approved in Codex's \
                        config.toml, because Codex quietly skips hooks nobody has \
                        approved.
                        """
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                if isCline {
                    Text("One file per event: \(clineFiles).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !precise.clineOccupied().isEmpty {
                        let occupied = precise.clineOccupied().joined(separator: ", ")
                        Text("Skipped, already taken by your own scripts: \(occupied)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    if installing { ProgressView().controlSize(.small).padding(.trailing, 6) }
                    Button(action: add) {
                        HStack(spacing: 5) {
                            Image(nsImage: ProviderMark.image(for: provider, size: 13))
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 13, height: 13)
                            Text(addTitle)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(installing)
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                unsafeToEdit
            }
        }
        .padding(22)
        .frame(width: 560)
    }

    private func add() {
        if isCodex {
            installing = true
            Task {
                _ = await precise.installCodex()
                installing = false
                onFinish()
                dismiss()
            }
        } else {
            if isCline { precise.installCline() } else { precise.install() }
            onFinish()
            dismiss()
        }
    }

    private var agentName: String {
        switch provider {
        case .codex: return "Codex"
        case .cline: return "Cline"
        default: return "Claude Code"
        }
    }

    private var addTitle: LocalizedStringKey {
        switch provider {
        case .codex: return "Add to Codex"
        case .cline: return "Add to Cline"
        default: return "Add to Claude Code"
        }
    }

    /// The six names, spelled out so the person can find them again.
    private var clineFiles: String {
        ["TaskStart", "TaskResume", "TaskCancel", "TaskComplete", "TaskError", "SessionShutdown"]
            .map { $0 + ".sh" }.joined(separator: ", ")
    }

    @ViewBuilder
    private var unsafeToEdit: some View {
        Text(
            """
            Belay will not edit this file, because it is not plain JSON. It may \
            have comments or a format Belay cannot write back safely. Add this \
            yourself instead:
            """
        )
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)

        if !isCodex, !isCline, let snippet = precise.manualSnippet() {
            codeBlock(snippet)
            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snippet, forType: .string)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    private func codeBlock(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        // Fixed, not a cap: Claude's JSON fills any height and Cline's short
        // script filled almost none, so the three sheets read as three sizes.
        // One height makes them one sheet.
        .frame(height: 280)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel("The exact configuration Belay will add")
    }
}
