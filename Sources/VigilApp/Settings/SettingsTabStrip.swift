import SwiftUI

/// The Settings window's pane switcher, drawn rather than delegated to AppKit.
///
/// It replaced an `NSToolbar` in `.preference` style, which looked right and
/// behaved right but drew its own selection: the highlight cut from one item to
/// the next, and there is no supported way in.
///
/// So the highlight is ours. It travels across the items in between rather than
/// reappearing at the destination, and its two edges do not travel together —
/// the leading edge lags the trailing one by a beat, so the pill stretches as it
/// sets off and gathers itself as it lands. That lag is the whole effect. With
/// both edges on one animation it is a rectangle sliding, which is what every
/// segmented control already does.
///
/// The rest of the toolbar's job is kept: fixed width, no overflow chevron,
/// nothing that can resize the window from underneath.
struct SettingsTabStrip: View {
    @Bindable var model: SettingsTabModel

    /// Matched to the spring. Much beyond this and the pill reads as two
    /// separate edges rather than as one that is stretching.
    static let lag: TimeInterval = 0.07
    private static let travel = Animation.spring(duration: 0.34, bounce: 0.28)

    @State private var frames: [SettingsPane: CGRect] = [:]
    /// Where the pill is now, in the strip's own coordinates. Kept as two edges
    /// rather than an origin and a width for exactly the reason above.
    @State private var leading: CGFloat?
    @State private var trailing: CGFloat?

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack(alignment: .topLeading) {
            pill
            HStack(spacing: 2) {
                ForEach(SettingsPane.allCases) { pane in
                    tab(pane)
                }
            }
        }
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(TabFrames.self) { frames = $0 }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onChange(of: model.pane) { _, pane in move(to: pane) }
        .onChange(of: frames) { _, _ in if leading == nil { settle() } }
        .accessibilityElement(children: .contain)
    }

    private static let space = "vigil.settings.tabs"

    /// The chip AppKit used to draw: a pane of something lying on the strip,
    /// lit from above and edged with a hairline, not a grey rectangle. Only its
    /// travel is ours; how it looks is meant to be indistinguishable.
    private var pill: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.primary.opacity(0.11), .primary.opacity(0.06)],
                    startPoint: .top, endPoint: .bottom)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.primary.opacity(0.13), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.16), radius: 1.5, y: 0.5)
            .frame(
                width: max((trailing ?? 0) - (leading ?? 0), 0),
                height: frames[model.pane]?.height ?? 0
            )
            .offset(x: leading ?? 0)
            .opacity(leading == nil ? 0 : 1)
            .accessibilityHidden(true)
    }

    private func tab(_ pane: SettingsPane) -> some View {
        Button {
            model.select(pane)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: pane.symbol)
                    .font(.system(size: 17, weight: .regular))
                    .frame(height: 20)
                Text(pane.title)
                    .font(.system(size: 11))
            }
            .foregroundStyle(tint(pane))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: TabFrames.self,
                    value: [pane: geometry.frame(in: .named(Self.space))])
            }
        }
        .accessibilityLabel(Text(verbatim: pane.title))
        .accessibilityAddTraits(model.pane == pane ? [.isButton, .isSelected] : .isButton)
    }

    private func tint(_ pane: SettingsPane) -> AnyShapeStyle {
        guard model.pane == pane else {
            return AnyShapeStyle(contrast == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        return AnyShapeStyle(.tint)
    }

    /// The first frame the strip is laid out on: the pill has to be somewhere
    /// before it can travel, and it must not travel from nowhere.
    private func settle() {
        guard let frame = frames[model.pane] else { return }
        leading = frame.minX
        trailing = frame.maxX
    }

    private func move(to pane: SettingsPane) {
        guard let frame = frames[pane], let from = leading else { return settle() }
        let delay = Self.delays(forward: frame.minX > from)
        withAnimation(Self.travel.delay(delay.leading)) { leading = frame.minX }
        withAnimation(Self.travel.delay(delay.trailing)) { trailing = frame.maxX }
    }

    /// The edge in front sets off first and the one behind follows a beat later,
    /// which is the stretch. Swap these and the pill squashes into its direction
    /// of travel, which reads as a mistake rather than as weight.
    static func delays(forward: Bool) -> (leading: TimeInterval, trailing: TimeInterval) {
        forward ? (leading: lag, trailing: 0) : (leading: 0, trailing: lag)
    }
}

/// What the strip talks to. The window owns the selection; the strip only asks
/// for it to change, so there is one place that knows which pane is showing.
@MainActor
@Observable
final class SettingsTabModel {
    var pane: SettingsPane
    var onSelect: (SettingsPane) -> Void = { _ in }

    init(pane: SettingsPane) {
        self.pane = pane
    }

    func select(_ pane: SettingsPane) {
        guard pane != self.pane else { return }
        onSelect(pane)
    }
}

private struct TabFrames: PreferenceKey {
    static let defaultValue: [SettingsPane: CGRect] = [:]

    static func reduce(
        value: inout [SettingsPane: CGRect], nextValue: () -> [SettingsPane: CGRect]
    ) {
        value.merge(nextValue()) { _, next in next }
    }
}
