import BelayModules
import SwiftUI

/// Settings ▸ Modules: what Belay can do beside its one job, each extra off
/// until it is installed.
struct ModulesPane: View {
    var host: ModuleHost
    /// The list changed height: a card opened, a search narrowed it.
    var onReshaped: () -> Void = {}

    var body: some View {
        @Bindable var browsing = host.browsing
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ModuleSearchField(text: $browsing.query)
                Picker(selection: $browsing.scope) {
                    Text("All").tag(ModuleBrowsing.Scope.all)
                    Text("Installed").tag(ModuleBrowsing.Scope.installed)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            if host.shown.isEmpty {
                Text(emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)
            } else {
                VStack(spacing: 10) {
                    ForEach(host.shown) { module in
                        ModuleCard(module: module, host: host)
                    }
                }
            }
        }
        .onChange(of: browsing.query) { onReshaped() }
        .onChange(of: browsing.scope) { onReshaped() }
        .onChange(of: browsing.expanded) { onReshaped() }
        .onChange(of: host.ledger) { onReshaped() }
        .onChange(of: host.screenshots.rules.folders) { onReshaped() }
        .onChange(of: host.screenshots.unreadable) { onReshaped() }
        .onChange(of: host.microphone.warmth) { onReshaped() }
        .onChange(of: host.autoAllow.standing) { onReshaped() }
        .onChange(of: host.autoAllow.rules.scope) { onReshaped() }
        .onChange(of: host.autoAllow.log) { onReshaped() }
    }

    private var emptyMessage: LocalizedStringKey {
        host.browsing.query.allSatisfy(\.isWhitespace)
            ? "Nothing installed yet." : "No modules match your search."
    }
}

/// A search field drawn to sit beside the segmented control at its height.
struct ModuleSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search modules", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isFocused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear"))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(isFocused ? 0.6 : 0), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }
}
