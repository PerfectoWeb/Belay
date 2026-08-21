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
        /// Something new arrived: the What's New window. Comes up from below.
        case whatsNew = "whats-new"
        /// The word writing itself on the welcome screen. The one recorded
        /// sound beside the cinematic below — see the note over `sound(_:)`.
        case welcomeSpell = "welcome-spell"
        /// The scene arriving, once ever: starts as the sky comes up and rings
        /// through the first pass, whatever else is still sounding.
        case welcomeCinematic = "welcome-cinematic"
        /// The keys under the scene's first act. A bed, not a strike.
        case welcomeTyping = "welcome-typing"
        /// An agent finishing, in the welcome scene. A bubble, not a chime.
        case agentPop = "agent-pop"
        /// The Mac letting go, in the welcome scene. Slow, low and quiet.
        case driftingOff = "drifting-off"
        /// And coming back: the same two notes the other way up.
        case wakingUp = "waking-up"
    }

    static var isEnabled: () -> Bool = { true }

    /// Playback gain per sound, applied at load. The synthesised files carry
    /// their levels in `make-sounds.swift`; the recordings arrive at whatever
    /// level they were mastered at, and this is where they are seated into
    /// the set — tuned by ear, 2026-08-19.
    private static let gains: [Sound: Float] = [
        .welcomeSpell: 0.8,
        .welcomeCinematic: 0.8,
        .whatsNew: 0.8
    ]

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

    /// How many notes the statistics chart has to choose from: the bar files
    /// `make-sounds.swift` renders, one per step of a pentatonic run.
    static let barSteps = 14

    /// Which note a bar plays, from its height against the tallest bar. The
    /// tallest gets the top of the run, an empty bar is never asked (the chart
    /// does not react to empty days), and everything between is quantised onto
    /// the scale — so a sweep across the chart plays its outline.
    static func barStep(held: Double, peak: Double) -> Int {
        guard peak > 0, held > 0 else { return 0 }
        return min(barSteps - 1, Int((held / peak * Double(barSteps - 1)).rounded()))
    }

    /// The statistics chart under the cursor: one struck note, pitched by
    /// `barStep`. Cached like the others, looked up by file name because a
    /// run of fourteen would swamp `Sound`.
    static func playBar(step: Int) {
        guard isEnabled(), systemPlaysInterfaceSounds else { return }
        let name = String(format: "bar-%02d", min(max(step, 0), barSteps - 1) + 1)
        if bars[name] == nil, let url = Bundle.main.url(forResource: name, withExtension: "wav") {
            bars[name] = NSSound(contentsOf: url, byReference: false)
        }
        guard let note = bars[name] else { return }
        note.stop()
        note.play()
    }

    private static var bars: [String: NSSound] = [:]

    /// Silences a sound mid-flight. Exists for the two long welcome
    /// recordings: a window closed at second three of a fifteen-second piece
    /// must not leave twelve seconds of soundtrack playing over nothing.
    static func stop(_ sound: Sound) {
        loaded[sound]?.stop()
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

    /// Most sounds are synthesised by `make-sounds.swift` and arrive as WAV;
    /// the two welcome recordings are MP3s that no script can regenerate,
    /// which is a deliberate exception to the everything-is-a-function rule —
    /// their provenance and licences live in NOTICE.md.
    private static func sound(_ sound: Sound) -> NSSound? {
        if let cached = loaded[sound] { return cached }
        let url =
            Bundle.main.url(forResource: sound.rawValue, withExtension: "wav")
            ?? Bundle.main.url(forResource: sound.rawValue, withExtension: "mp3")
        guard let url, let effect = NSSound(contentsOf: url, byReference: false) else { return nil }
        effect.volume = gains[sound] ?? 1
        loaded[sound] = effect
        return effect
    }

    /// The system-wide switch in Sound settings. Absent means on, which is how
    /// macOS itself reads it.
    private static var systemPlaysInterfaceSounds: Bool {
        UserDefaults.standard.object(forKey: "com.apple.sound.uiaudio.enabled") as? Bool ?? true
    }
}
