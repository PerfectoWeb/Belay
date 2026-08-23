import AppKit
import SwiftUI

/// A SwiftUI label that drops a `DurationMenu` when clicked. The label is
/// drawn by SwiftUI; the only AppKit on screen is the menu itself.
struct DurationMenuButton<Label: View>: View {
    let current: TimeInterval?
    let choose: (TimeInterval?) -> Void
    @ViewBuilder let label: () -> Label

    @State private var anchor = MenuAnchor()

    var body: some View {
        Button {
            anchor.show(current: current, choose: choose)
        } label: {
            label()
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(MenuAnchorView(anchor: anchor))
    }
}

/// Holds the AppKit view the menu hangs from, and the menu itself.
@MainActor
final class MenuAnchor {
    fileprivate weak var view: NSView?
    private var menu: DurationMenu?

    func show(current: TimeInterval?, choose: @escaping (TimeInterval?) -> Void) {
        guard let view else { return }
        let menu = DurationMenu(choose: choose)
        menu.askCustom = { current in
            if let seconds = CustomDuration.ask(current: current) { choose(seconds) }
        }
        self.menu = menu
        menu.show(from: view, current: current)
    }
}

private struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}
