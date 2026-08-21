import AppKit

/// The frosted layer under the dim clock: one click-through panel per display
/// carrying a behind-window blur, so whatever was on screen becomes shapes
/// and colours rather than words.
///
/// The gamma ramp cannot do this — it multiplies pixels, it does not mix them
/// — so this is the one place the dimmer puts a window on screen. It does
/// two things the ramp alone did not: hides the work from a passer-by, and
/// gives the clock a plain ground to sit on. The ramp stays; the veil is
/// added on top, and the blur's own dark tint is why the screen reads darker
/// than the dim level alone would make it.
@MainActor
final class DimVeil {
    private var panels: [NSPanel] = []

    /// The clock sits one step above this; both live above full-screen apps.
    static let level = NSWindow.Level.screenSaver

    /// How much of the frost shows. The blur radius itself is the system
    /// material's and cannot be set without private filters, so strength is
    /// the panel's opacity: at 1 only the blurred picture is visible, and
    /// below that the sharp one shows through in proportion — which reads as
    /// a lighter blur and a lighter tint together. 0.85, by eye: at a half the
    /// text showed through readable, at three quarters it wanted one more step.
    static let strength: CGFloat = 0.85

    func show() {
        guard panels.isEmpty else { return }
        for screen in NSScreen.screens {
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = Self.level
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

            let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: screen.frame.size))
            effect.material = .fullScreenUI
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.autoresizingMask = [.width, .height]
            panel.contentView = effect

            // Fades up on the ramp's own timing (one second down), so the
            // frost arrives with the dark rather than snapping over it.
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 1.0
                panel.animator().alphaValue = Self.strength
            }
            panels.append(panel)
        }
    }

    /// Quick on the way out, like the ramp's restore: a return that takes a
    /// second to clear reads as a broken Mac.
    func hide() {
        let leaving = panels
        panels.removeAll()
        guard !leaving.isEmpty else { return }
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.3
                for panel in leaving { panel.animator().alphaValue = 0 }
            },
            completionHandler: {
                Task { @MainActor in
                    for panel in leaving { panel.orderOut(nil) }
                }
            })
    }
}
