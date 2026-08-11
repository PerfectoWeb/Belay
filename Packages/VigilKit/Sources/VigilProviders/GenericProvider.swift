import Foundation
import VigilCore
import VigilSupport

/// The provider that covers every agent Vigil has no first-class support for.
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
        displayName: "Other agents",
        summary: """
            Watches a folder you choose, or listens for a one-line webhook, so any \
            coding agent can hold the Mac awake. Start from a preset or add your own.
            """,
        symbolName: "square.stack.3d.up",
        supportsPreciseDetection: false)

    public let signals: AsyncStream<ActivitySignal>

    let access: FileAccessProvider
    let clock: any Clock
    let roster: @Sendable () -> Set<String>?
    private let continuation: AsyncStream<ActivitySignal>.Continuation
    let queue = DispatchQueue(label: "com.perfecto-web.vigil.providers.generic", qos: .utility)

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
            return .needsSetup("Add a folder to watch, or pick a preset, to cover another agent.")
        }
        let unreachable = configured.compactMap(\.watchedFolder).first { !access.hasAccess(to: $0) }
        guard let unreachable else { return .ready }
        return .needsSetup("Let Vigil read \(unreachable.lastPathComponent) so it can see that agent work.")
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
    /// Gemini's mark rather than the "some other agent" one. Targets the user
    /// built by hand have none, and get the neutral mark.
    private func preset(of watch: GenericWatch) -> String? {
        guard let owner = watch.target else { return nil }
        return targets.first { $0.id == owner }?.webhookIdentifier
    }
}
