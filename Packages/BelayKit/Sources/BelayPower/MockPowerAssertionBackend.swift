import Foundation

/// An in-memory backend that records everything and can be made to fail.
///
/// Ships in the product module rather than the test target so the app can run
/// against it during UI work without touching real power management.
public actor MockPowerAssertionBackend: PowerAssertionBackend {
    /// One entry per attempted call, in order, including attempts that failed.
    public enum Call: Sendable, Equatable {
        case create(kind: PowerAssertionKind, reason: String, timeout: TimeInterval)
        case rearm(id: PowerAssertionID, reason: String, timeout: TimeInterval)
        case release(id: PowerAssertionID)
    }

    public enum Operation: Sendable, Equatable, CaseIterable {
        case create
        case rearm
        case release
    }

    /// `kIOReturnError`, the generic IOKit failure, spelled out so the mock
    /// does not need to link IOKit.
    public static let defaultFailureCode: Int32 = -536_870_212

    public private(set) var calls: [Call] = []
    public private(set) var liveIDs: [PowerAssertionID: PowerAssertionKind] = [:]

    private var failing: Set<Operation> = []
    private var failureCode = MockPowerAssertionBackend.defaultFailureCode
    private var nextRawID: UInt32 = 1

    public init() {}

    /// Makes the listed operations throw until `stopFailing()` is called.
    public func fail(
        _ operations: Set<Operation>,
        code: Int32 = MockPowerAssertionBackend.defaultFailureCode
    ) {
        failing = operations
        failureCode = code
    }

    public func stopFailing() {
        failing = []
    }

    public var createCount: Int { calls.filter(\.isCreate).count }
    public var rearmCount: Int { calls.filter(\.isRearm).count }
    public var releaseCount: Int { calls.filter(\.isRelease).count }

    public func liveCount(of kind: PowerAssertionKind) -> Int {
        liveIDs.values.filter { $0 == kind }.count
    }

    public func create(
        kind: PowerAssertionKind,
        reason: String,
        timeout: TimeInterval
    ) async throws(PowerError) -> PowerAssertionID {
        calls.append(.create(kind: kind, reason: reason, timeout: timeout))
        guard !failing.contains(.create) else { throw PowerError.assertionFailed(code: failureCode) }
        let id = PowerAssertionID(rawValue: nextRawID)
        nextRawID += 1
        liveIDs[id] = kind
        return id
    }

    public func rearm(
        _ id: PowerAssertionID,
        reason: String,
        timeout: TimeInterval
    ) async throws(PowerError) {
        calls.append(.rearm(id: id, reason: reason, timeout: timeout))
        guard !failing.contains(.rearm) else { throw PowerError.assertionFailed(code: failureCode) }
        // Re-arming a dead handle is a controller bug, and tests should see it.
        guard liveIDs[id] != nil else { throw PowerError.assertionFailed(code: failureCode) }
    }

    public func release(_ id: PowerAssertionID) async throws(PowerError) {
        calls.append(.release(id: id))
        guard !failing.contains(.release) else { throw PowerError.assertionFailed(code: failureCode) }
        guard liveIDs.removeValue(forKey: id) != nil else {
            throw PowerError.assertionFailed(code: failureCode)
        }
    }
}

extension MockPowerAssertionBackend.Call {
    public var isCreate: Bool {
        if case .create = self { true } else { false }
    }

    public var isRearm: Bool {
        if case .rearm = self { true } else { false }
    }

    public var isRelease: Bool {
        if case .release = self { true } else { false }
    }
}
