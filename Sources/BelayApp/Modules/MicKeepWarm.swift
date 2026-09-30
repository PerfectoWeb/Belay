import BelayModules
import Foundation
import Observation

/// The microphone keep-warm, running: holds the microphone open while
/// nothing stands in the way, and says why when something does.
@MainActor
@Observable
final class MicKeepWarm {
    /// How long a change has to stay quiet before the microphone is opened
    /// again. Plugging in a headset announces itself several times over.
    static let settle: Duration = .seconds(3)

    var rules: MicRules {
        didSet {
            guard rules != oldValue else { return }
            rules.save(to: defaults)
            refresh()
        }
    }
    private(set) var warmth: MicWarmth = .off {
        didSet {
            guard warmth != oldValue else { return }
            Diagnostics.note("mic state=\(warmth)")
        }
    }
    /// The microphone being held, as macOS names it.
    private(set) var microphone: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let tap: MicTap
    @ObservationIgnored private let surroundings: MicSurroundings
    @ObservationIgnored private let settle: Duration
    @ObservationIgnored private var isEnabled = false
    @ObservationIgnored private var isOpen = false
    @ObservationIgnored private var unwatch: (() -> Void)?
    @ObservationIgnored private var reopening: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        tap: MicTap = CaptureMicTap(),
        surroundings: MicSurroundings = .real,
        settle: Duration = MicKeepWarm.settle
    ) {
        self.defaults = defaults
        self.tap = tap
        self.surroundings = surroundings
        self.settle = settle
        rules = MicRules.load(from: defaults)
    }

    /// Switched on by the user: the one moment macOS may be asked for the
    /// microphone, because the question then follows from what they did.
    func activate() {
        start()
        guard surroundings.permission() == .undecided else { return }
        surroundings.ask { [weak self] _ in self?.refresh() }
    }

    func start() {
        guard !isEnabled else { return }
        isEnabled = true
        tap.whenDisturbed { [weak self] in
            Task { @MainActor in self?.reopenOnceSettled() }
        }
        unwatch = surroundings.watch { [weak self] in self?.refresh() }
        refresh()
    }

    func stop() {
        isEnabled = false
        unwatch?()
        unwatch = nil
        refresh()
    }

    /// Looks at everything again and holds or lets go accordingly.
    func refresh() {
        let wanted = MicWarmth.decide(
            isEnabled: isEnabled, permission: surroundings.permission(),
            isOnBattery: surroundings.isOnBattery(), input: surroundings.inputKind(),
            rules: rules)
        guard wanted == .warm else {
            letGo()
            warmth = wanted
            return
        }
        guard !isOpen else { return }
        open()
    }

    private func open() {
        isOpen = true
        tap.open { [weak self] name in
            Task { @MainActor in self?.opened(name) }
        }
    }

    private func opened(_ name: String?) {
        // Switched off, or put on the battery, while the microphone was
        // starting: what just opened is let go again.
        guard isOpen else {
            tap.close()
            return
        }
        microphone = name
        warmth = name == nil ? .noMicrophone : .warm
        // How it is connected, never what it is called: the name is often
        // somebody's own.
        guard name != nil else { return }
        Diagnostics.note("mic opened kind=\(surroundings.inputKind()?.rawValue ?? "none")")
    }

    private func letGo() {
        reopening?.cancel()
        reopening = nil
        guard isOpen else { return }
        isOpen = false
        microphone = nil
        tap.close()
        Diagnostics.note("mic released")
    }

    private func reopenOnceSettled() {
        guard isOpen else { return }
        reopening?.cancel()
        reopening = Task { [weak self, settle] in
            try? await Task.sleep(for: settle)
            guard !Task.isCancelled, let self, self.isOpen else { return }
            self.open()
        }
    }

    /// Removing the module: the rules go, the permission stays with macOS.
    func forgetEverything() {
        stop()
        rules = MicRules()
        defaults.removeObject(forKey: MicRules.defaultsKey)
    }
}
