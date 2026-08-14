import AppKit
import BelayCore

/// The sounds and the one haptic Belay makes.
///
/// Belay is a utility that is meant to be forgotten about, so almost nothing it
/// does makes a noise. These are the exceptions, and they are all the same kind
/// of moment: something the user did by hand, where the only other confirmation
/// is a small mark changing colour somewhere they may not be looking.
///
/// Three gates before anything plays, in order of authority: the system's
/// "play user interface sound effects" preference, Belay's own switch, and
/// whether the sound exists at all. macOS does not apply the first one to
/// `NSSound` for us, so ignoring it is a choice, and it is the wrong one.
///
/// The wiring is a static closure rather than an injected object because sound
/// is not owned by any one view: the mode can be changed from the panel, and
/// the same rule has to hold in Settings and in About. It is set once, at
/// launch, from the preference store.
@MainActor
enum Feedback {
    enum Sound: String, CaseIterable {
        /// Rising: Belay decides for itself again.
        case auto = "mode-auto"
        /// Held: an override, and it should sound like one.
        case alwaysOn = "mode-always"
        /// Falling, and the quietest of the three.
        case off = "mode-off"
        /// A button did something. Level pitch, barely there.
        case tick
        /// The only sound here that is about the person rather than the machine.
        case thanks
        /// An agent finishing, in the welcome scene. A bubble, not a chime.
        case agentPop = "agent-pop"
        /// The Mac letting go, in the welcome scene. Slow, low and quiet.
        case driftingOff = "drifting-off"
        /// And coming back: the same two notes the other way up.
        case wakingUp = "waking-up"
    }

    static var isEnabled: () -> Bool = { true }

    /// Loaded once each. Eight files of about 30 KB, which is cheaper than
    /// reading them off disk at the moment somebody is watching for a response.
    private static var loaded: [Sound: NSSound] = [:]

    static func play(_ sound: Sound) {
        guard isEnabled(), systemPlaysInterfaceSounds else { return }
        guard let effect = self.sound(sound) else { return }
        // Stopped first so a second tap restarts it rather than being swallowed:
        // switching modes twice in a row has to sound like two switches.
        effect.stop()
        effect.play()
    }

    /// A tick under the finger on a Force Touch trackpad, and nothing at all on
    /// anything else. `.levelChange` is the pattern Apple reserves for exactly
    /// this — a control moving between discrete positions.
    static func levelChanged() {
        guard isEnabled() else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    static func sound(for mode: AwakeMode) -> Sound {
        switch mode {
        case .auto: return .auto
        case .alwaysOn: return .alwaysOn
        case .off: return .off
        }
    }

    private static func sound(_ sound: Sound) -> NSSound? {
        if let cached = loaded[sound] { return cached }
        guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav"),
            let effect = NSSound(contentsOf: url, byReference: false)
        else { return nil }
        loaded[sound] = effect
        return effect
    }

    /// The system-wide switch in Sound settings. Absent means on, which is how
    /// macOS itself reads it.
    private static var systemPlaysInterfaceSounds: Bool {
        UserDefaults.standard.object(forKey: "com.apple.sound.uiaudio.enabled") as? Bool ?? true
    }
}
