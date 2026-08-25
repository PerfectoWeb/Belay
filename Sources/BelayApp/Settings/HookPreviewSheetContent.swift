import BelayCore
import SwiftUI

/// The two subviews the sheet falls back to. Beside `HookPreviewSheet` for the
/// file-length rule.
extension HookPreviewSheet {
    @ViewBuilder
    var unsafeToEdit: some View {
        if let snippet = manualSnippet {
            // A snippet is available (Claude Code): promise it, then show it.
            Text(
                """
                Belay will not edit this file, because it is not plain JSON. It \
                may have comments or a format Belay cannot write back safely. \
                Add this yourself instead:
                """
            )
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
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
            // No snippet to hand over (Codex/Cline, or an unreadable file): say
            // so honestly rather than promising a snippet that never appears.
            Text(
                """
                Belay will not change \(path), because it is not in a format it \
                can edit safely. Fix its format and open this again, and Belay \
                will show you the exact change to review.
                """
            )
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    func codeBlock(_ text: String) -> some View {
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
