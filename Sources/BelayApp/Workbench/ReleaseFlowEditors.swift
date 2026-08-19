#if DEBUG
import AppKit
import SwiftUI
import WebKit

/// The two notes tabs of `ReleaseFlow`, editable in place.
///
/// They write straight back to the files in the checkout — the same files
/// the release pipeline ships — because this window only ever runs from a
/// local debug build sitting inside that checkout. Saving is explicit: a
/// half-typed sentence must never be what `publish-appcast.sh` picks up.
struct NotesTab: View {
    let file: URL
    @State private var mode = Mode.preview
    @State private var revision = 0

    enum Mode { case preview, edit }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: relative(file)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker(selection: $mode) {
                    Text(verbatim: "Preview").tag(Mode.preview)
                    Text(verbatim: "Edit").tag(Mode.edit)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            if mode == .preview {
                if let html = try? String(contentsOf: file, encoding: .utf8) {
                    // Transparent page over the well colour: the HTML brings
                    // its own dark-mode text colours, and a hard white sheet
                    // in a dark window was the first thing anybody noticed.
                    WebPage(html: html, base: file.deletingLastPathComponent(), revision: revision)
                        .background(Color(nsColor: .underPageBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    FileEditor(file: file) { revision += 1 }
                }
            } else {
                FileEditor(file: file) { revision += 1 }
            }
        }
        .padding()
    }
}

struct StoreTab: View {
    let file: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: relative(file)).font(.caption).foregroundStyle(.secondary)
            FileEditor(file: file) {}
        }
        .padding()
    }
}

/// Repo-relative, for the caption: the absolute path is noise.
@MainActor private func relative(_ file: URL) -> String {
    file.path.replacingOccurrences(of: ReleaseFlow.repo.path + "/", with: "")
}

/// A plain text editor over one file: load on appear, save on demand, and an
/// honest dot when the buffer and the disk disagree.
struct FileEditor: View {
    let file: URL
    var saved: () -> Void

    @State private var text = ""
    @State private var onDisk = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .underPageBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack(spacing: 8) {
                Button {
                    save()
                } label: {
                    Text(verbatim: "Save")
                }
                .disabled(text == onDisk)
                if text != onDisk {
                    Text(verbatim: "unsaved changes")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        let read = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        text = read
        onDisk = read
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
            onDisk = text
            saved()
        } catch {
            // A debug window may be blunt.
            NSSound.beep()
        }
    }
}

/// Renders the HTML the way Sparkle's dialog will, minus the white sheet:
/// the page draws no background of its own here, so the well colour behind
/// it does the theming.
private struct WebPage: NSViewRepresentable {
    let html: String
    let base: URL
    let revision: Int

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        // Not exposed as API on macOS, and fine in a DEBUG-only window: it is
        // the one switch that stops WKWebView painting white under the page.
        view.setValue(false, forKey: "drawsBackground")
        view.loadHTMLString(html, baseURL: base)
        context.coordinator.shown = revision
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.shown != revision else { return }
        context.coordinator.shown = revision
        view.loadHTMLString(html, baseURL: base)
    }

    func makeCoordinator() -> Shown { Shown() }

    final class Shown {
        var shown = -1
    }
}
#endif
