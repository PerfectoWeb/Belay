#if DEBUG
import AppKit
import SwiftUI

/// The release workbench: one debug window that walks the whole flow.
///
/// It replaced three loose menu items. Before a release the same things have
/// to be looked at every time — the screens, the Sparkle notes, the store
/// text — and the same chores done in order. This window puts the looking
/// behind tabs and the chores behind checkboxes, keyed by version.
///
/// Debug builds only, enforced twice: the whole file is `#if DEBUG`, and
/// `StatusMenuTests` fails a release build whose menu offers any of it. The
/// notes tabs read the repository checkout via `#filePath` — a trick only a
/// debug window may play.
@MainActor
enum ReleaseFlow {
    private static var window: NSWindow?

    static func present(
        showWelcome: @escaping () -> Void,
        showWhatsNew: @escaping () -> Void,
        pretendChanged: @escaping () -> Void
    ) {
        // Activation first, both paths: an accessory app's window can
        // otherwise land behind whatever is frontmost.
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let made = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        made.title = "Release Flow — \(Branding.version)"
        made.isReleasedWhenClosed = false
        made.center()
        made.contentView = NSHostingView(
            rootView: ReleaseFlowView(
                showWelcome: showWelcome, showWhatsNew: showWhatsNew,
                pretendChanged: pretendChanged))
        window = made
        made.makeKeyAndOrderFront(nil)
    }

    /// The repository this debug build was compiled from.
    static var repo: URL {
        URL(fileURLWithPath: #filePath)  // …/Sources/BelayApp/Workbench/ReleaseFlowWindow.swift
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct ReleaseFlowView: View {
    let showWelcome: () -> Void
    let showWhatsNew: () -> Void
    let pretendChanged: () -> Void

    var body: some View {
        TabView {
            ScreensTab(
                showWelcome: showWelcome, showWhatsNew: showWhatsNew,
                pretendChanged: pretendChanged
            )
            .tabItem { Text(verbatim: "Screens") }
            NotesTab(
                file: ReleaseFlow.repo
                    .appendingPathComponent("docs/release-notes/Belay-\(Branding.version).html")
            )
            .tabItem { Text(verbatim: "Sparkle notes") }
            StoreTab(
                file: ReleaseFlow.repo
                    .appendingPathComponent("docs/release-notes/appstore-\(Branding.version).txt")
            )
            .tabItem { Text(verbatim: "App Store") }
            ChecklistTab()
                .tabItem { Text(verbatim: "Checklist") }
        }
        .padding(12)
    }
}

private struct ScreensTab: View {
    let showWelcome: () -> Void
    let showWhatsNew: () -> Void
    let pretendChanged: () -> Void
    @State private var pretending = ReleaseChecker.isPretending

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: "Every screen a release shows, replayable from its first frame.")
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button {
                    showWelcome()
                } label: {
                    Text(verbatim: "Welcome")
                }
                Button {
                    showWhatsNew()
                } label: {
                    Text(verbatim: "What's New")
                }
            }
            Toggle(isOn: $pretending) {
                Text(verbatim: "Pretend Update — the next check offers the test feed")
            }
            .onChange(of: pretending) { _, on in
                ReleaseChecker.isPretending = on
                pretendChanged()
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

/// The chores, in release order, ticked as they happen. State lives in
/// UserDefaults under the version, so cutting 1.4.0 starts a fresh sheet and
/// the 1.3.x sheet stays as the record of what was done.
private struct ChecklistTab: View {
    private static let steps: [(id: String, name: String)] = [
        ("version", "project.yml: MARKETING_VERSION and CURRENT_PROJECT_VERSION bumped"),
        ("changelog", "CHANGELOG.md has this version's section"),
        ("whatsnew", "ReleaseNote.swift: entry replaced, strings translated x7"),
        ("sparkle", "docs/release-notes/Belay-<version>.html written"),
        ("appstore", "docs/release-notes/appstore-<version>.txt written"),
        ("roadmap", "ROADMAP rows and header updated"),
        ("readme", "README claims still true for this version"),
        ("gate", "scripts/test.sh green on the release tree"),
        ("masverify", "scripts/verify-mas-build.sh clean"),
        ("release", "release.sh run, DMG notarized and stapled"),
        ("published", "gh release create, both DMGs uploaded"),
        ("appcast", "publish-appcast.sh --publish"),
        ("cask", "bump-cask.sh after the release is public"),
        ("organizer", "MAS archive in Xcode Organizer, store notes handed over")
    ]

    @State private var ticked: Set<String> = ChecklistTab.load()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "\(ticked.count) of \(Self.steps.count) done for \(Branding.version)")
                .font(.caption)
                .foregroundStyle(ticked.count == Self.steps.count ? .green : .secondary)
            List {
                ForEach(Self.steps, id: \.id) { step in
                    Toggle(isOn: binding(step.id)) { Text(verbatim: step.name) }
                        .padding(.vertical, 4)
                }
            }
            Button {
                ticked = []
                Self.store([])
            } label: {
                Text(verbatim: "Reset this version's sheet")
            }
            .controlSize(.small)
        }
        .padding()
    }

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { ticked.contains(id) },
            set: { on in
                if on { ticked.insert(id) } else { ticked.remove(id) }
                Self.store(ticked)
            })
    }

    private static var key: String { "releaseFlow.\(Branding.version)" }

    private static func load() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    private static func store(_ ticked: Set<String>) {
        UserDefaults.standard.set(ticked.sorted(), forKey: key)
    }
}
#endif
