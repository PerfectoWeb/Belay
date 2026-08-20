import BelayCore
import BelaySupport
import Foundation

/// The provider that covers every agent Belay has no first-class support for.
///
/// Three strategies, each usable alone (`docs/03` "Generic provider"):
/// a folder whose contents change, a process name that must still be alive, and
/// a routed local webhook. Presets are configurations of this actor, not
/// subclasses of it — including Codex CLI, per `PROJECT_STATE` D4.
///
/// One actor hosts every target instead of one actor per target: `ProviderID` is
/// the identity the bus and the settings pane work in, and there is exactly one
/// `.generic` case. It also makes the timer budget trivially correct — N
/// configured targets share one 5 s ticker and one FSEvents stream per distinct
/// folder, not N of each.
///
/// Everything here is `.inferred`, webhook reports included: a local caller
/// asserting "I am busy" is a hint from an unverified tool, and must never be
/// able to override an `.exact` idle from the hook bridge.
public actor GenericProvider: ActivityProvider {
    /// Idle resolution. Process liveness is refreshed every third tick, i.e. 15 s.
    static let tickInterval: TimeInterval = 5

    nonisolated public let descriptor = ProviderDescriptor(
        id: .generic,
        displayName: String(localized: "Other agents", bundle: .main),
        summary: String(
            localized: """
                Watches a folder you choose, or listens for a one-line webhook, so any \
                coding agent can hold the Mac awake. Start from a preset or add your own.
                """, bundle: .main),
        symbolName: "square.stack.3d.up",
        supportsPreciseDetection: false)

    public let signals: AsyncStream<ActivitySignal>

    let access: FileAccessProvider
    let clock: any Clock
    let roster: @Sendable () -> Set<String>?
    private let continuation: AsyncStream<ActivitySignal>.Continuation
    let queue = DispatchQueue(label: "com.perfectoweb.belay.providers.generic", qos: .utility)

    var targets: [GenericTarget]
    var watches: [SessionID: GenericWatch] = [:]
    /// Keyed by resolved folder path: two targets watching the same folder share
    /// one stream, which is also what makes "watch my home folder" survivable.
    var streams: [String: FileEventStream] = [:]
    var followers: [String: [GenericTarget.ID]] = [:]
    var liveProcesses: Set<String> = []
    var ticker: DispatchSourceTimer?
    var tickCount = 0
    private var isStarted = false

    public init(
        targets: [GenericTarget] = [],
        access: FileAccessProvider = DirectFileAccess(),
        clock: any Clock = SystemClock(),
        roster: (@Sendable () -> Set<String>?)? = nil
    ) {
        self.targets = targets
        self.access = access
        self.clock = clock
        // Injectable so a test can name a process that does not exist without
        // asking the machine's real process table to play along.
        self.roster = roster ?? { ProcessRoster.scan() }
        let made = AsyncStream.makeStream(
            of: ActivitySignal.self, bufferingPolicy: .bufferingNewest(256))
        signals = made.stream
        continuation = made.continuation
    }

    deinit {
        continuation.finish()
    }

    public var availability: ProviderAvailability {
        let configured = targets.filter(\.isConfigured)
        guard !configured.isEmpty else {
            return .needsSetup(
                String(
                    localized: "Add a folder to watch, or pick a preset, to cover another agent.",
                    bundle: .main))
        }
        let unreachable = configured.compactMap(\.watchedFolder).first { !access.hasAccess(to: $0) }
        guard let unreachable else { return .ready }
        // Two different problems wear the same badge, and the words must not
        // lie about which one it is. A folder that does not exist is not a
        // permission problem: the tool has never run here (or lives
        // elsewhere), and asking the user to "allow" it would send them
        // hunting for a grant that fixes nothing.
        let shown = Self.abbreviated(unreachable)
        guard FileManager.default.fileExists(atPath: unreachable.path) else {
            return .needsSetup(
                String(
                    localized: """
                        No \(shown) yet. It appears once the tool has run. \
                        Adjust the folder if yours is elsewhere.
                        """,
                    bundle: .main))
        }
        return .needsSetup(
            String(
                localized: "Let Belay read \(shown) so it can see that agent work.",
                bundle: .main))
    }

    /// "~/.codex/sessions" rather than "sessions": the bare last component
    /// told the user nothing about which tool the badge was even about.
    static func abbreviated(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    /// Never throws on a bad target. One misconfigured folder must not take the
    /// other targets — or Tier A — down with it; it shows as `needsSetup`.
    public func start() async throws {
        guard !isStarted else { return }
        isStarted = true
        liveProcesses = roster() ?? []
        rebuildStreams()
        startTicking()
    }

    public func stop() async {
        for stream in streams.values { stream.stop() }
        streams.removeAll()
        followers.removeAll()
        ticker?.cancel()
        ticker = nil
        watches.removeAll()
        liveProcesses.removeAll()
        tickCount = 0
        isStarted = false
    }

    /// Applies an edited configuration in place. Sessions belonging to targets
    /// the user removed end immediately rather than ageing out of the ledger.
    public func configure(_ updated: [GenericTarget]) {
        let now = clock.now
        let surviving = Set(updated.map(\.id))
        targets = updated
        for (id, watch) in watches {
            guard let owner = watch.target, !surviving.contains(owner) else { continue }
            end(id, at: now)
        }
        guard isStarted else { return }
        rebuildStreams()
    }

    // MARK: - Emitting

    func report(_ activity: SessionActivity, for id: SessionID, at now: Date) {
        guard var watch = watches[id] else { return }
        // `.working` repeats deliberately — the coordinator reads it as a
        // heartbeat and wants a fresh timestamp. Repeating `.idle` is just noise.
        guard activity == .working || activity != watch.reported else { return }
        watch.reported = activity
        watches[id] = watch
        yield(activity, from: watch, at: now)
    }

    func end(_ id: SessionID, at now: Date) {
        guard let watch = watches.removeValue(forKey: id) else { return }
        yield(.ended, from: watch, at: now)
    }

    private func yield(_ activity: SessionActivity, from watch: GenericWatch, at now: Date) {
        continuation.yield(
            ActivitySignal(
                provider: .generic,
                session: watch.id,
                activity: activity,
                workspace: watch.workspace,
                kind: preset(of: watch),
                timestamp: now,
                confidence: .inferred))
    }

    /// The preset a target was created from, which is how the UI knows to show
    /// Gemini's mark rather than the "some other agent" one.
    ///
    /// A target built by hand carries no preset id, and used to get the neutral
    /// mark for ever after. But somebody who adds a folder and names the row
    /// "Codex" has told us which tool it is as plainly as picking the preset
    /// would have, and the app already ships that logo. So the name is matched
    /// against the presets as a fallback. Only an exact match counts, ignoring
    /// case and spacing: a guess here puts the wrong company's mark on a row.
    private func preset(of watch: GenericWatch) -> String? {
        guard let owner = watch.target, let target = targets.first(where: { $0.id == owner })
        else { return nil }
        if let identifier = target.webhookIdentifier { return identifier }
        return GenericPreset.matching(name: target.displayName)?.id
    }
}
