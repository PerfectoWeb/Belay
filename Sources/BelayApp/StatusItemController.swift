import AppKit
import BelayCore
import BelaySupport

/// Owns the menu bar item.
///
/// The image is always a template image; that flag is what makes light, dark,
/// tinted and reduced-transparency menu bars work without a single colour
/// literal in this file. State is conveyed by shape, never by animation: a
/// pulsing menu bar icon burns a redraw every frame and reads as cheap
/// (docs/05).
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let state: AppState
    private let panel: PanelController
    /// Built once and popped up manually on right-click. Assigning it to
    /// `statusItem.menu` would hand left-click to the menu, which is the
    /// panel's.
    /// Made fresh on each right-click: the update row and the workbench tick
    /// read state as they are drawn, and a menu built once shows what was true
    /// at first launch.
    private var contextMenu: NSMenu { makeMenu() }

    /// A look and whether an update is waiting: the two things that decide which
    /// image goes in the button.
    private struct Key: Hashable {
        let look: BelayGlyph.Look
        let waiting: Bool
    }

    /// Every frame of every look, rendered once at startup, so animating costs
    /// one property assignment per tick rather than a redraw (docs/08).
    ///
    /// Both update states are rendered up front for the same reason. Drawing the
    /// dotted variant at the moment a check lands would put a redraw on the
    /// path that is supposed to be free.
    private lazy var frames: [Key: [NSImage]] = {
        var table: [Key: [NSImage]] = [:]
        for look in [BelayGlyph.Look.alwaysOn, .working, .resting, .calling, .off, .blocked] {
            let count = look.isAnimated ? BelayGlyph.frameCount : 1
            for waiting in [false, true] {
                table[Key(look: look, waiting: waiting)] = (0..<count).map {
                    BelayGlyph.statusItemImage(look, frame: $0, waiting: waiting)
                }
            }
        }
        return table
    }()

    private var ticker: Timer?
    private var frame = 0
    private var look: BelayGlyph.Look = .resting
    private var waiting = false

    /// Whether an update is waiting, asked rather than stored, so the answer
    /// cannot go stale between a check landing and the next redraw. Set by the
    /// app: the checker lives with Settings.
    var isUpdateWaiting: () -> Bool = { false }

    /// One callback for every menu destination: the menu names a pane, the app
    /// decides how to show it.
    var onOpenPane: (SettingsPane) -> Void = { _ in }

    /// What the update row says and does. Set by the app: the checker lives
    /// with Settings rather than here.
    var updateStatus: () -> (title: String, waiting: Bool)? = { nil }
    var onUpdate: () -> Void = {}

    /// Records that this version is not wanted. Separate from `onUpdate` because
    /// the two are opposites and sharing one hook would need a flag.

    /// Built lazily and popped up by hand, so a test cannot see it otherwise.
    var menuForTesting: NSMenu { contextMenu }

    /// The workbench destinations, stored here because an extension cannot.
    var onShowWelcome: () -> Void = {}
    var onShowWhatsNew: () -> Void = {}
    var onPretendUpdateChanged: () -> Void = {}

    init(state: AppState, panel: PanelController) {
        self.state = state
        self.panel = panel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
        render()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func handleClick() {
        guard let button = statusItem.button else { return }
        let isRightClick =
            NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true
        if isRightClick {
            statusItem.menu = contextMenu
            button.performClick(nil)
            statusItem.menu = nil
        } else {
            panel.toggle(relativeTo: button)
        }
    }

    /// Re-renders from `AppState`. Called by the app after each state change
    /// rather than by an observer, so nothing redraws while nothing changed.
    func render() {
        guard let button = statusItem.button else { return }
        let appearance = Appearance(state: state.snapshot.state)
        let next = BelayGlyph.Look(state: state.snapshot.state)
        if next != look {
            look = next
            frame = 0
            retimeAnimation()
        }
        let nextWaiting = isUpdateWaiting()
        if nextWaiting != waiting { waiting = nextWaiting }
        button.image = frames[Key(look: look, waiting: waiting)]?[frame]
        button.image?.accessibilityDescription = appearance.label
        button.setAccessibilityLabel(appearance.label)
        button.toolTip = appearance.label
    }

    /// The timer exists only while an agent is working. In every other state the
    /// icon is a still image and nothing is scheduled, so an idle Belay wakes for
    /// this exactly never.
    private func retimeAnimation() {
        ticker?.invalidate()
        ticker = nil
        guard look.isAnimated else { return }
        scheduleNextFrame()
    }

    /// One-shot per frame rather than one repeating timer, because the frames
    /// are not equally long: the shimmer runs fast and the last frame is held.
    /// A repeating timer at the shimmer rate would keep waking the app through
    /// the hold, which is the entire cost of a menu bar animation.
    private func scheduleNextFrame() {
        let delay = BelayGlyph.frameDuration(frame)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.look.isAnimated else { return }
                self.frame = (self.frame + 1) % BelayGlyph.frameCount
                self.statusItem.button?.image =
                    self.frames[Key(look: self.look, waiting: self.waiting)]?[self.frame]
                self.scheduleNextFrame()
            }
        }
        // A tenth of the interval of slack lets the scheduler coalesce this with
        // whatever else is waking up, which is most of the saving.
        timer.tolerance = delay / 10
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private struct Appearance {
        let label: String

        init(state: BelayState) {
            switch state {
            case .off:
                label = String(localized: "Belay is off. Your Mac will sleep normally.")
            case .armed:
                label = String(localized: "Belay is watching. Your Mac will sleep normally.")
            case .working, .coolingDown:
                label = String(localized: "Belay is keeping your Mac awake: an agent is working.")
            case .alwaysOn:
                label = String(localized: "Belay is keeping your Mac awake: always on.")
            case .awaitingUser:
                label = String(localized: "An agent is waiting for you. Belay is keeping your Mac awake.")
            case .suspended(let reason):
                switch reason {
                case .batteryLow(let charge):
                    let percent = Int((charge * 100).rounded())
                    label = String(localized: "Belay stopped holding: battery is at \(percent)%.")
                case .maxDurationReached:
                    label = String(localized: "Belay stopped holding: the maximum awake time was reached.")
                case .timerEnded:
                    label = String(localized: "Belay stopped holding: the timer ran out.")
                }
            }
        }
    }

    @objc func openSettings() {
        onOpenPane(.general)
    }

    @objc func openStatistics() {
        onOpenPane(.statistics)
    }

    @objc func openAbout() {
        onOpenPane(.about)
    }

    /// Quitting stops Belay holding the Mac awake, and a mis-click here means an
    /// overnight run dies quietly hours later. Cheap to confirm, expensive not to.
    @objc func confirmQuit() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Quit \(Branding.appName)?")
        alert.informativeText =
            state.isHolding
            ? String(localized: "An agent is working. Your Mac will be free to sleep as soon as Belay quits.")
            : String(localized: "Your Mac will go back to its normal sleep schedule.")
        alert.addButton(withTitle: String(localized: "Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSApp.terminate(nil)
    }

    deinit {
        MainActor.assumeIsolated {
            ticker?.invalidate()
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }
}

extension AwakeMode {
    var title: String {
        switch self {
        case .auto: return "Auto"
        case .alwaysOn: return "Always on"
        case .off: return "Off"
        }
    }
}
