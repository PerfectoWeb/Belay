import SwiftUI
import VigilProviders

/// The measurements of the "Other tools" grid.
///
/// The measurements of the "Other tools" list.
///
/// Two per row, inside the control column where the "Add a tool…" menu lives.
/// Spanning the whole pane put the tiles hard against the left margin and broke
/// the label/control rhythm every other row in Settings keeps; one per row left
/// half the column empty. Two of the `[mark][name over detail]` rows fit the
/// column with the detail line still readable.
enum TargetTileMetrics {
    static let spacing: CGFloat = 6
    static let corner: CGFloat = 8
    static let markSize: CGFloat = 22
    static let padding: CGFloat = 8

    /// How a tile arrives and how it goes.
    ///
    /// A tile that appears fully formed reads as the list having been replaced,
    /// and one that vanishes leaves you checking whether you removed the right
    /// thing. Arriving is the livelier of the two on purpose: adding a tool is
    /// something the user chose and the tile should look pleased about it, while
    /// removing one should be quick and quiet and get out of the way.
    static let arrival = Animation.spring(duration: 0.38, bounce: 0.34)
    static let departure = Animation.spring(duration: 0.26, bounce: 0)

    /// Grows from just under full size rather than from nothing: scaling all the
    /// way from zero is a magic trick, and this is a row appearing in a list.
    static var transition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.88).combined(with: .opacity),
            removal: .scale(scale: 0.82).combined(with: .opacity))
    }

    /// The control column of a `SettingRow` at the pane's fixed width.
    static let columnWidth =
        SettingsPane.width - SettingsMetrics.paneInsets.leading
        - SettingsMetrics.paneInsets.trailing - SettingsMetrics.labelWidth
        - SettingsMetrics.columnGap
}

/// The configured generic targets, as tiles rather than as a form.
///
/// A row per target read as "here is a field and its value"; these are things the
/// user added, and a set of things you added looks like a set of things.
struct GenericTargetGrid: View {
    let targets: [GenericTarget]
    let remove: (GenericTarget) -> Void

    /// Fixed at two rather than `.adaptive`: adaptive silently drops to one on a
    /// narrower column, and this column is not narrow — it just is not wide
    /// enough for three with a readable detail line.
    private static let columns = Array(
        repeating: GridItem(.flexible(), spacing: TargetTileMetrics.spacing, alignment: .top),
        count: 2)

    var body: some View {
        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: TargetTileMetrics.spacing) {
            ForEach(targets) { target in
                GenericTargetTile(target: target, remove: remove)
                    .transition(TargetTileMetrics.transition)
            }
        }
    }
}

/// One watched tool: its mark, its name, what Vigil is watching, and a way out.
struct GenericTargetTile: View {
    /// A target added by hand carries no preset id. `ProviderMark` answers an id
    /// it has never heard of with its neutral drawn mark, which is the right
    /// answer here — better an honest shape than another tool's logo.
    static let neutralMark = "generic"

    let target: GenericTarget
    let remove: (GenericTarget) -> Void
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var markPreset: String { target.webhookIdentifier ?? Self.neutralMark }

    /// What is actually being watched, in the words the old row used.
    var detail: String {
        var parts: [String] = []
        if let folder = target.watchedFolder { parts.append(folder.lastPathComponent) }
        if let process = target.processName { parts.append(String(localized: "process \(process)")) }
        return parts.isEmpty ? String(localized: "not configured") : parts.joined(separator: " · ")
    }

    /// The remove button's action, named so a test can fire it without
    /// synthesising a click on a hosted SwiftUI view.
    ///
    /// Focus is dropped first. Clicking the button focuses it, and the focus
    /// ring is drawn outside the tile's own bounds, so it does not scale away
    /// with the tile: it hangs in the air for the length of the animation and
    /// only vanishes when the view finally goes.
    func removeAction() {
        isFocused = false
        isHovering = false
        remove(target)
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(presetMark: markPreset, size: TargetTileMetrics.markSize)
                .resizable()
                .interpolation(.high)
                .frame(width: TargetTileMetrics.markSize, height: TargetTileMetrics.markSize)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(target.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 18)
        }
        .padding(TargetTileMetrics.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: TargetTileMetrics.corner)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: TargetTileMetrics.corner)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
        .overlay(alignment: .topTrailing) { removeButton }
        .onHover { isHovering = $0 }
    }

    /// Hover only changes its opacity. Gating its existence on the mouse would
    /// put it out of reach of the keyboard and of VoiceOver, so it is always
    /// there, and focusing it makes it visible for the same reason.
    private var removeButton: some View {
        Button(action: removeAction) {
            Image(systemName: "xmark.circle.fill")
                .imageScale(.medium)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($isFocused)
        .padding(5)
        .opacity(isHovering || isFocused ? 1 : 0.35)
        .accessibilityLabel("Remove \(target.displayName)")
        .accessibilityHint("Stops Vigil watching this tool")
    }
}
