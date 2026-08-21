import AppKit
import BelayCore
import SwiftUI

/// The countdown on the dimmed screen: white monospaced digits, nothing else.
///
/// The gamma ramp is what makes this work at all. A dimmed display multiplies
/// every pixel down, ours included, so plain white text lands at exactly the
/// screen's pre-dim brightness — the brightest anything can be under the ramp.
/// The digits read as cut out of the darkness without a second dimming
/// mechanism or any compensation here.
///
/// StandBy is the pattern: a dim clock on a dark screen at night, and nothing
/// asking to be looked at. The window takes no clicks, no focus, and drifts a
/// few points a minute the way Apple's own night faces do, out of respect for
/// OLED panels.
@MainActor
final class DimClock {
    private var panel: NSPanel?
    private var drift: Timer?
    /// Steps through `driftOffsets`; position is a pure function of it.
    private var driftStep = 0

    /// A small closed loop around the anchor, one step a minute. Deterministic
    /// on purpose — nothing here needs randomness, and a repeating walk of
    /// ±8 pt spreads wear just as well.
    private static let driftOffsets: [CGPoint] = [
        CGPoint(x: 0, y: 0), CGPoint(x: 8, y: 4), CGPoint(x: -3, y: 8), CGPoint(x: -8, y: 2),
        CGPoint(x: -4, y: -6), CGPoint(x: 5, y: -8), CGPoint(x: 8, y: -2), CGPoint(x: 2, y: 6)
    ]

    /// Whether the clock belongs on screen. Pure, so the rule is testable
    /// without a display: the screen is dimmed, the user wants it, and there
    /// is a countdown to show — an unbounded hold has nothing to count.
    static func shouldShow(dimmed: Bool, enabled: Bool, timer: AlwaysOnTimer?) -> Bool {
        dimmed && enabled && timer != nil
    }

    /// Idempotent, called from the dimmer's tick: shows, hides, or re-targets
    /// as the state asks. The deadline can move while the clock is up — the
    /// user picked a different duration — so a visible clock re-hosts when it
    /// changes.
    func sync(dimmed: Bool, enabled: Bool, timer: AlwaysOnTimer?) {
        guard Self.shouldShow(dimmed: dimmed, enabled: enabled, timer: timer), let timer else {
            hide()
            return
        }
        show(deadline: timer.deadline)
    }

    private var shownDeadline: Date?

    private func show(deadline: Date) {
        if panel != nil, shownDeadline == deadline { return }
        shownDeadline = deadline

        let host = NSHostingView(rootView: DimClockView(deadline: deadline))
        host.frame.size = host.fittingSize

        if let panel {
            panel.contentView = host
            panel.setContentSize(host.frame.size)
            place(panel)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: host.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        // Above the dim, below nothing that matters: the screen saver level
        // keeps the digits over full-screen apps without ever taking focus.
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = host
        self.panel = panel

        place(panel)
        panel.orderFrontRegardless()

        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.driftOnce() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        drift = timer
    }

    func hide() {
        shownDeadline = nil
        drift?.invalidate()
        drift = nil
        driftStep = 0
        panel?.orderOut(nil)
        panel = nil
    }

    /// Bottom centre of the main screen, a tenth of the height up — where a
    /// screensaver clock sits, far from the menu bar and any window chrome.
    private func place(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let offset = Self.driftOffsets[driftStep % Self.driftOffsets.count]
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: screen.frame.midX - size.width / 2 + offset.x,
                y: screen.frame.minY + screen.frame.height * 0.1 + offset.y))
    }

    private func driftOnce() {
        guard let panel else { return }
        driftStep += 1
        place(panel)
    }
}

/// The digits themselves. `Text(timerInterval:)` ticks on its own, so no timer
/// of ours runs for the seconds — only the once-a-minute drift above.
struct DimClockView: View {
    let deadline: Date

    var body: some View {
        Text(timerInterval: min(Date.now, deadline)...deadline, countsDown: true)
            .font(.system(size: 28, weight: .light))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.9))
            .padding(4)
    }
}
