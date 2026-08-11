import Foundation
import IOKit.pwr_mgt

/// The real thing: `IOPMAssertionCreateWithProperties` and friends.
///
/// Every assertion is born with `kIOPMAssertionTimeoutKey` and
/// `kIOPMAssertionTimeoutActionRelease`. That is the safety design, not a
/// detail (docs/04): if Vigil crashes, wedges or is killed, the kernel drops
/// the assertion within the timeout window and the Mac sleeps normally again.
public struct IOKitPowerAssertionBackend: PowerAssertionBackend {
    private let localizationBundlePath: String

    /// `localizationBundlePath` is the bundle macOS localises the reason string
    /// against before showing it in `pmset -g assertions` and the Battery menu.
    public init(localizationBundlePath: String = Bundle.main.bundlePath) {
        self.localizationBundlePath = localizationBundlePath
    }

    public func create(
        kind: PowerAssertionKind,
        reason: String,
        timeout: TimeInterval
    ) async throws(PowerError) -> PowerAssertionID {
        var id = IOPMAssertionID(0)
        var properties: [String: Any] = [:]
        properties[kIOPMAssertionTypeKey] = kind.assertionType
        properties[kIOPMAssertionNameKey] = "Vigil"
        properties[kIOPMAssertionDetailsKey] = reason
        properties[kIOPMAssertionHumanReadableReasonKey] = reason
        properties[kIOPMAssertionLocalizationBundlePathKey] = localizationBundlePath
        properties[kIOPMAssertionTimeoutKey] = timeout as NSNumber
        properties[kIOPMAssertionTimeoutActionKey] = kIOPMAssertionTimeoutActionRelease

        let status = IOPMAssertionCreateWithProperties(properties as CFDictionary, &id)
        guard status == kIOReturnSuccess else { throw PowerError.assertionFailed(code: status) }
        return PowerAssertionID(rawValue: id)
    }

    public func rearm(
        _ id: PowerAssertionID,
        reason: String,
        timeout: TimeInterval
    ) async throws(PowerError) {
        // Re-setting the timeout restarts the countdown, which is cheaper and
        // less racy than release-and-recreate; the details key keeps
        // `pmset -g assertions` truthful about which session we are waiting on.
        try set(id, key: kIOPMAssertionTimeoutKey, value: timeout as NSNumber)
        try set(id, key: kIOPMAssertionDetailsKey, value: reason as NSString)
    }

    public func release(_ id: PowerAssertionID) async throws(PowerError) {
        let status = IOPMAssertionRelease(IOPMAssertionID(id.rawValue))
        guard status == kIOReturnSuccess else { throw PowerError.assertionFailed(code: status) }
    }

    private func set(_ id: PowerAssertionID, key: String, value: CFTypeRef) throws(PowerError) {
        let status = IOPMAssertionSetProperty(IOPMAssertionID(id.rawValue), key as CFString, value)
        guard status == kIOReturnSuccess else { throw PowerError.assertionFailed(code: status) }
    }
}

extension PowerAssertionKind {
    var assertionType: String {
        switch self {
        case .system: kIOPMAssertionTypePreventUserIdleSystemSleep
        case .display: kIOPMAssertionTypePreventUserIdleDisplaySleep
        }
    }
}
