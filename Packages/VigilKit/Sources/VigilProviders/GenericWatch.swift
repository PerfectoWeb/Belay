import Foundation
import VigilCore

/// One live generic session.
///
/// A session is keyed by an arbitrary identifier rather than by a file, because
/// the three strategies produce different kinds of evidence: a folder change, a
/// routed webhook report, or nothing at all while a process quietly exits. The
/// identifier is what lets any of them land on the same session.
struct GenericWatch: Sendable {
    let id: SessionID
    /// The target this session belongs to, or `nil` for a webhook session from a
    /// tool the user never configured — that path has to work with no setup.
    let target: GenericTarget.ID?
    var workspace: String?
    /// Last evidence of work. Drives the quiet-period idle rule.
    var lastActivityAt: Date
    var quietPeriod: TimeInterval
    /// Last activity yielded, so `.idle` is not repeated every sweep while
    /// `.working` stays a heartbeat the coordinator can refresh from.
    var reported: SessionActivity?
}
