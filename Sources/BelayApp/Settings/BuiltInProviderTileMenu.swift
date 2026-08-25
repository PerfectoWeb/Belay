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
            // folders are removable, and removal is the click itself.
            Button {
            } label: {
                Label(home, systemImage: "house")
            }
            .disabled(true)
            if !provider.customRoots.isEmpty {
                Text("Click a folder to stop watching it")
                ForEach(provider.customRoots, id: \.self) { path in
                    Button {
                        onRemoveRoot(path)
                    } label: {
                        Label(
                            (path as NSString).abbreviatingWithTildeInPath,
                            systemImage: "folder")
                    }
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
