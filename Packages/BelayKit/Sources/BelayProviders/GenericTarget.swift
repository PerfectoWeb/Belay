import BelayCore
import Foundation

/// One thing the generic provider watches, as configured by the user.
///
/// This is the whole of the "covers everything else without a code change"
/// promise (PRD R8): a folder, a process name, a webhook identifier. Any one of
/// the three is usable on its own, and a target may combine them.
///
/// Deliberately *not* modelled: anything tool-specific. There is no DeepSeek
/// target, because there is no first-party DeepSeek CLI to target — it is
/// reached through Cline, Aider and other clients, which are covered by a folder
/// and a process name like everything else (PRD R8).
public struct GenericTarget: Sendable, Equatable, Codable, Identifiable {
    /// Below this, one slow tool call reads as an idle turn. `docs/DISCOVERY`
    /// §2.2 measured ten silent seconds inside a single call on a real session,
    /// and that was not the worst case.
    public static let quietPeriodRange: ClosedRange<TimeInterval> = 15...600

    public var id: UUID
    public var displayName: String
    /// A modification anywhere under this folder means work is happening.
    public var watchedFolder: URL?
    /// Context only. Its absence ends the session; its presence never starts one
    /// (`docs/03` Tier C — a live process says nothing about being busy).
    public var processName: String?
    /// The `session` a routed webhook report must carry to land on this target.
    public var webhookIdentifier: String?
    /// No change for this long ends the turn.
    public var inferredIdleAfter: TimeInterval
    /// FSEvents coalescing window.
    public var latency: TimeInterval

    public init(
        id: UUID = UUID(),
        displayName: String,
        watchedFolder: URL? = nil,
        processName: String? = nil,
        webhookIdentifier: String? = nil,
        inferredIdleAfter: TimeInterval = 45,
        latency: TimeInterval = 1.0
    ) {
        self.id = id
        self.displayName = displayName
        self.watchedFolder = watchedFolder
        self.processName = processName?.isEmpty == true ? nil : processName
        self.webhookIdentifier = webhookIdentifier?.isEmpty == true ? nil : webhookIdentifier
        let quiet = Self.quietPeriodRange
        self.inferredIdleAfter = min(max(inferredIdleAfter, quiet.lowerBound), quiet.upperBound)
        self.latency = min(max(latency, 0.1), 5)
    }

    /// A target with none of the three strategies set can never signal anything,
    /// so the provider ignores it rather than pretending it is watching.
    public var isConfigured: Bool {
        watchedFolder != nil || processName != nil || webhookIdentifier != nil
    }

    /// Sessions are namespaced by target so two generic targets watching two
    /// folders are two sessions in the ledger, not one flickering between them.
    public var session: SessionID { SessionID("generic:\(id.uuidString)") }
}

/// A state report routed in from Belay's loopback hook receiver.
///
/// The receiver itself belongs to `BelayHookBridge` and is deliberately neither
/// duplicated nor imported here: this module owns *what a report means*, that
/// module owns the socket. The app layer already runs the listener, so routing a
/// generic report is one call — `await generic.ingest(report)` — for any tool
/// that can run a shell command in a hook:
///
///     curl -s -m 1 "http://127.0.0.1:$PORT/hook?token=$TOKEN&provider=generic\
///     &session=aider&state=working" >/dev/null 2>&1 || true
///
/// `session` is arbitrary and chosen by the caller. A report whose identifier
/// matches a configured target is attributed to it; anything else becomes its
/// own session, so integrating needs no prior configuration at all.
public struct GenericWebhookReport: Sendable, Equatable {
    public let identifier: String
    public let activity: SessionActivity
    public let workspace: String?

    public init(identifier: String, activity: SessionActivity, workspace: String? = nil) {
        self.identifier = identifier
        self.activity = activity
        self.workspace = workspace
    }

    /// The `state=` vocabulary lives in `BelayCore` so the receiver, this
    /// provider and the README cannot drift apart. An unknown state is dropped,
    /// never guessed.
    public init?(identifier: String, state: String, workspace: String? = nil) {
        guard !identifier.isEmpty, let activity = SessionActivity(webhookState: state) else {
            return nil
        }
        self.init(identifier: identifier, activity: activity, workspace: workspace)
    }
}
