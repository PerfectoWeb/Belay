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
    @Environment(\.dismiss) var dismiss
    /// True while the codex install runs: writing the file is instant, but
    /// recording the approval spawns `codex app-server` and takes a moment.
    @State private var installing = false
    /// The preview and its neighbours are read from disk once, on appear, rather
    /// than recomputed on every body evaluation — the old computed properties
    /// re-parsed the agent's settings file each render, which stalls on a slow
    /// or network home volume.
    @State private var loaded = false
    @State private var proposed: String?
    @State private var occupied: [String] = []
    @State var manualSnippet: String?

    private var isCodex: Bool { provider == .codex }
    private var isCline: Bool { provider == .cline }
    var path: String {
        switch provider {
        case .codex: return precise.codexHooksPath
        case .cline: return precise.clineHooksPath
        default: return precise.settingsPath
        }
    }

    /// What the sheet shows as "will be written": Cline's is one script that
    /// lands under six event names, the other two are the merged JSON.
    private func loadPreview() {
        guard !loaded else { return }
        switch provider {
        case .codex: proposed = precise.codexPreview()?.proposed
        case .cline:
            proposed = precise.clinePreview()
            occupied = precise.clineOccupied()
        default:
            proposed = precise.preview()?.proposed
            manualSnippet = precise.manualSnippet()
        }
        loaded = true
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

            if !loaded {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else if let preview = proposed {
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
                if precise.extraRootsCount(for: provider) > 0 {
                    Text("The same change is made in every folder Belay watches for this agent.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                    if !occupied.isEmpty {
                        Text(
                            "Skipped, already taken by your own scripts: "
                                + "\(occupied.joined(separator: ", "))"
                        )
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
        .task { loadPreview() }
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
}
