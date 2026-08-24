import XCTest

@testable import Belay

/// The toggle that would not turn off.
///
/// It bound straight to `SMAppService.mainApp.status`, and that status is served
/// by a daemon that has not caught up by the time the view redraws — so an
/// `unregister()` that had in fact succeeded read back as `.enabled` and the
/// tick reappeared. Every test here is about the control agreeing with what
/// actually happened.

/// `@unchecked Sendable` because `LoginItemService` is `Sendable` and this stub
/// holds mutable state. It is only ever touched from the `@MainActor` test body,
/// one test at a time, and nothing hands it to another isolation domain.
private final class FakeService: LoginItemService, @unchecked Sendable {
    var registered = false
    var approvalPending = false
    var failure: Error?
    /// The bug in one flag: the service keeps answering with the old value for a
    /// while after a successful call.
    var reportsStaleStatus = false

    var isRegistered: Bool { reportsStaleStatus ? !registered : registered }
    var needsApproval: Bool { approvalPending }

    func register() throws {
        if let failure { throw failure }
        registered = true
    }

    func unregister() throws {
        if let failure { throw failure }
        registered = false
    }
}

private struct Refused: LocalizedError {
    var errorDescription: String? { "Operation not permitted" }
}

@MainActor
final class LoginItemTests: XCTestCase {
    func testTurningItOffStaysOffEvenWhileMacOSStillSaysOn() async {
        let service = FakeService()
        service.registered = true
        let item = LoginItem(service: service)
        await item.refreshNow()
        XCTAssertTrue(item.isEnabled)

        service.reportsStaleStatus = true
        item.set(false)

        XCTAssertFalse(service.registered, "unregister was not called")
        XCTAssertFalse(item.isEnabled, "the checkbox put itself back on — this is the reported bug")
        XCTAssertNil(item.problem)
    }

    func testTurningItOnSticks() {
        let service = FakeService()
        let item = LoginItem(service: service)
        service.reportsStaleStatus = true
        item.set(true)
        XCTAssertTrue(service.registered)
        XCTAssertTrue(item.isEnabled)
    }

    /// A control that claims success it did not have is worse than one that
    /// refuses, so a throw snaps the state back to what macOS really thinks.
    func testARefusalShowsTheReasonAndDoesNotLie() {
        let service = FakeService()
        service.registered = true
        service.failure = Refused()
        let item = LoginItem(service: service)

        item.set(false)

        XCTAssertTrue(item.isEnabled, "the tick must reflect macOS, not the click")
        XCTAssertEqual(item.problem, .refused("Operation not permitted"))
    }

    func testApprovalPendingIsItsOwnCase() async {
        let service = FakeService()
        service.approvalPending = true
        let item = LoginItem(service: service)
        await item.refreshNow()
        XCTAssertEqual(item.problem, .needsApproval)

        service.approvalPending = false
        await item.refreshNow()
        XCTAssertNil(item.problem, "the note outlived the condition")
    }

    /// The first fix put the bug back through the side door: `refresh()` runs on
    /// `windowDidBecomeKey`, which fires on every reopen and after every sheet,
    /// and it trusted the daemon unconditionally. Untick, reopen Settings, tick
    /// is back — and the second time it looks worse, because the user believes
    /// they already fixed it.
    func testReopeningSettingsDoesNotUndoTheChange() async {
        let service = FakeService()
        service.registered = true
        var now = Date(timeIntervalSince1970: 1_760_000_000)
        let item = LoginItem(service: service, clock: { now })

        service.reportsStaleStatus = true
        item.set(false)
        now += 1
        await item.refreshNow()

        XCTAssertFalse(item.isEnabled, "the daemon lagging must not read as the user changing it back")
    }

    /// The trust window is bounded: once it lapses the service is believed
    /// again, so a real outside change is never ignored for good.
    func testTheDaemonIsBelievedOnceItHasHadTimeToCatchUp() async {
        let service = FakeService()
        var now = Date(timeIntervalSince1970: 1_760_000_000)
        let item = LoginItem(service: service, clock: { now })

        item.set(true)
        service.registered = false
        now += LoginItem.settlingPeriod + 1
        await item.refreshNow()

        XCTAssertFalse(item.isEnabled)
    }

    /// The user can revoke this in System Settings while the window is open.
    func testRefreshPicksUpAnOutsideChange() async {
        let service = FakeService()
        service.registered = true
        let item = LoginItem(service: service)
        await item.refreshNow()
        XCTAssertTrue(item.isEnabled)

        service.registered = false
        await item.refreshNow()
        XCTAssertFalse(item.isEnabled)
    }

    func testTheBindingWritesThrough() {
        let service = FakeService()
        let item = LoginItem(service: service)
        item.binding.wrappedValue = true
        XCTAssertTrue(service.registered)
        XCTAssertTrue(item.binding.wrappedValue)
    }
}
