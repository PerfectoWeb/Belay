import Foundation

@testable import BelayPower

/// A backend that parks inside a call until the test lets it out.
///
/// `MockPowerAssertionBackend` answers instantly, which means the window
/// `reconcile` suspends in is never open long enough to put anything in it. This
/// one holds the window open on demand, so an interleaving can be *arranged*
/// rather than waited for.
actor GatedPowerAssertionBackend: PowerAssertionBackend {
    private(set) var live: [PowerAssertionID: PowerAssertionKind] = [:]
    private(set) var createCount = 0
    private(set) var releaseCount = 0

    /// The most assertions of a kind ever live *at the moment another was
    /// requested*. Counted on entry rather than on completion because the
    /// question is whether a second create was ever issued against a live one;
    /// which of the two parked calls the runtime resumes first is not the point.
    private(set) var peak: [PowerAssertionKind: Int] = [:]

    private var isOpen = false
    private var parked: [CheckedContinuation<Void, Never>] = []
    private var arrivals: [CheckedContinuation<Void, Never>] = []
    private var nextRawID: UInt32 = 1

    func liveCount(of kind: PowerAssertionKind) -> Int {
        live.values.filter { $0 == kind }.count
    }

    func peakCount(of kind: PowerAssertionKind) -> Int {
        peak[kind] ?? 0
    }

    /// Resolves once some call is parked in the gate.
    func waitForParkedCall() async {
        guard parked.isEmpty else { return }
        await withCheckedContinuation { arrivals.append($0) }
    }

    /// Lets every parked call through, and every later one straight past.
    func open() {
        isOpen = true
        for continuation in parked { continuation.resume() }
        parked = []
    }

    /// Re-arms the gate for the next call.
    func shut() {
        isOpen = false
    }

    func create(
        kind: PowerAssertionKind,
        reason: String,
        timeout: TimeInterval
    ) async throws(PowerError) -> PowerAssertionID {
        createCount += 1
        peak[kind] = max(peak[kind] ?? 0, liveCount(of: kind) + 1)
        await gate()
        let id = PowerAssertionID(rawValue: nextRawID)
        nextRawID += 1
        live[id] = kind
        return id
    }

    func rearm(_ id: PowerAssertionID, reason: String, timeout: TimeInterval) async throws(PowerError) {
        await gate()
        guard live[id] != nil else { throw PowerError.assertionFailed(code: -1) }
    }

    func release(_ id: PowerAssertionID) async throws(PowerError) {
        releaseCount += 1
        await gate()
        guard live.removeValue(forKey: id) != nil else {
            throw PowerError.assertionFailed(code: -1)
        }
    }

    private func gate() async {
        guard !isOpen else { return }
        for continuation in arrivals { continuation.resume() }
        arrivals = []
        await withCheckedContinuation { parked.append($0) }
    }
}
