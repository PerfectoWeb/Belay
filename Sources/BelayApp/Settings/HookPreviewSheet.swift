import SwiftUI

/// Shows exactly what will be written to `~/.claude/settings.json`, before
/// anything is written.
///
/// This sheet *is* the consent required by `docs/00-INVARIANTS.md` invariant 6. If the file
/// cannot be edited safely, it degrades to showing a snippet to copy rather than
/// refusing with no way forward — the user's agent config is theirs, and being
/// told "no" with no alternative is worse than being handed the text.
struct HookPreviewSheet: View {
    var precise: PreciseDetection
    var onFinish: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Enable precise detection")
                .font(.title3).bold()

            if let preview = precise.preview() {
                Text("Belay will change \(precise.settingsPath) to:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                codeBlock(preview.proposed)
                Text(
                    """
                    A timestamped backup is made first. Everything already in the \
                    file is preserved, and "Remove" puts it back exactly.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Add to Claude Code") {
                        precise.install()
                        onFinish()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                unsafeToEdit
            }
        }
        .padding(22)
        .frame(width: 560)
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

        if let snippet = precise.manualSnippet() {
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
        .frame(maxHeight: 260)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel("The exact configuration Belay will add")
    }
}
