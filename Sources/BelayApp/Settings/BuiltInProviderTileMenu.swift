import AppKit
import BelayCore
import SwiftUI

/// The tile's menu. Beside `BuiltInProviderTile` for the file-length rule.
extension BuiltInProviderTile {
    /// One menu, three entrances: the slider button, right-click, Control-click.
    @ViewBuilder
    var agentMenu: some View {
        if precise {
            Button {
                onRemovePrecise()
            } label: {
                Label("Remove Precise Detection", systemImage: "bolt.slash")
            }
        } else if offersPrecise {
            Button {
                onEnablePrecise()
            } label: {
                Label("Enable Precise Detection…", systemImage: "bolt")
            }
        }
        Menu {
            // The default home rides along for context; only the added
            // folders are removable, each through its own submenu so a stray
            // click cannot remove anything.
            Button {
            } label: {
                Label(home, systemImage: "house")
            }
            .disabled(true)
            ForEach(provider.customRoots, id: \.self) { path in
                Menu {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [URL(fileURLWithPath: path, isDirectory: true)])
                    } label: {
                        Label("Show in Finder", systemImage: "magnifyingglass")
                    }
                    Divider()
                    Button(role: .destructive) {
                        onRemoveRoot(path)
                    } label: {
                        Label("Remove Folder", systemImage: "trash")
                    }
                } label: {
                    Label((path as NSString).abbreviatingWithTildeInPath, systemImage: "folder")
                }
            }
            if !provider.suggestedRoots.isEmpty {
                Divider()
                Text("Found nearby")
                ForEach(provider.suggestedRoots, id: \.self) { path in
                    Button {
                        onAddSuggested(path)
                    } label: {
                        Label(
                            (path as NSString).abbreviatingWithTildeInPath,
                            systemImage: "folder.badge.plus")
                    }
                }
            }
            Divider()
            Button {
                onAddRoot()
            } label: {
                Label("Add Folder…", systemImage: "folder.badge.plus")
            }
        } label: {
            Label("Watched Folders", systemImage: "folder")
        }
    }
}
