import Foundation
import Testing

@testable import BelayHookBridge

/// Where the bundled codex is looked for, against a scratch ChatGPT.app.
@Suite("Codex binary lookup")
struct CodexBinaryTests {
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("belay-codex-\(UUID().uuidString)", isDirectory: true)

    private var resources: URL { root.appendingPathComponent("Contents/Resources", isDirectory: true) }

    private func plant(_ relative: String, executable: Bool = true, text: String = "#!/bin/sh\n") throws {
        let url = resources.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }

    private func locate() -> String? {
        CodexAppServer.locateBinary(onPath: [], chatGPT: root)?.path
    }

    @Test("The manifest's entry point wins in the codex-cli layout")
    func manifestEntryPoint() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try plant("codex-cli/codex-package.json", executable: false, text: #"{"entrypoint":"bin/codex"}"#)
        try plant("codex-cli/bin/codex")
        try plant("codex")
        #expect(locate() == resources.appendingPathComponent("codex-cli/bin/codex").path)
    }

    @Test("Without a manifest the launcher in bin is still found")
    func launcherWithoutManifest() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try plant("codex-cli/bin/codex")
        #expect(locate() == resources.appendingPathComponent("codex-cli/bin/codex").path)
    }

    @Test("The flat path of an older ChatGPT still counts")
    func olderFlatPath() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try plant("codex")
        #expect(locate() == resources.appendingPathComponent("codex").path)
    }

    @Test("A manifest naming a file that is not there falls through")
    func staleManifest() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try plant("codex-cli/codex-package.json", executable: false, text: #"{"entrypoint":"gone/codex"}"#)
        try plant("codex-cli/bin/codex", executable: false)
        #expect(locate() == nil)
    }
}
