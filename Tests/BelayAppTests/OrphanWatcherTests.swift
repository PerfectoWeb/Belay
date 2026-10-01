import BelayModules
import XCTest

@testable import Belay

/// No test here looks at the real process table or signals a real process:
/// the table is a list written by hand.
@MainActor
final class OrphanWatcherTests: XCTestCase {
    private var defaults: UserDefaults?
    private var suiteName = ""
    private let processes = FakeProcesses()
    private var lines: [String] = []

    override func setUp() async throws {
        suiteName = "com.perfectoweb.belay.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        lines = []
    }

    override func tearDown() async throws {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private func makeWatcher() throws -> OrphanWatcher {
        OrphanWatcher(
            defaults: try XCTUnwrap(defaults), source: processes, settle: .milliseconds(20),
            now: { FakeProcesses.epoch }, note: { [weak self] line in self?.lines.append(line) })
    }

    /// An agent with a shell and a dev server under it.
    private func startSession() {
        processes.put(100, "claude")
        processes.put(101, "zsh", parent: 100)
        processes.put(102, "node", parent: 101, started: 5)
    }

    private func endSession() {
        processes.drop(100)
        processes.drop(101)
    }

    func testNothingHappensBeforeItIsSwitchedOn() throws {
        startSession()
        let watcher = try makeWatcher()

        watcher.sweep()

        XCTAssertEqual(processes.reads, 0, "read the process table before activate")
        XCTAssertFalse(watcher.isRunning)
        XCTAssertTrue(watcher.findings.isEmpty)
        XCTAssertTrue(lines.isEmpty)
    }

    func testSwitchingOnLooksOnceAndFindsNothingWhileTheAgentLives() throws {
        startSession()
        let watcher = try makeWatcher()

        watcher.activate()

        XCTAssertEqual(processes.reads, 1)
        XCTAssertTrue(watcher.isRunning)
        XCTAssertTrue(watcher.findings.isEmpty)
        XCTAssertEqual(watcher.findings.roots, 1)
        XCTAssertEqual(
            lines.first, "orphans start spinning=1 percent=50 minutes=10 notifies=1 ignored=0")
        watcher.stop()
    }

    func testAVanishedAgentLeavesItsProcessListed() throws {
        startSession()
        let watcher = try makeWatcher()
        watcher.activate()

        endSession()
        watcher.sweep()

        XCTAssertEqual(watcher.findings.leftBehind.map(\.pid), [102])
        XCTAssertEqual(watcher.findings.leftBehind.first?.name, "node")
        XCTAssertEqual(watcher.findings.leftBehind.first?.agent, .claude)
        XCTAssertTrue(lines.contains("orphans sweep roots=0 tracked=1 orphans=1 hot=0"))
        watcher.stop()
    }

    func testTheSweepLineIsWrittenOnlyWhenTheNumbersChange() throws {
        startSession()
        let watcher = try makeWatcher()
        watcher.activate()
        watcher.sweep()
        watcher.sweep()

        XCTAssertEqual(lines.filter { $0.hasPrefix("orphans sweep") }.count, 1)
        watcher.stop()
    }

    func testAClaudeSessionFileNamesAnAgentWhateverItsProcessIsCalled() throws {
        processes.put(200, "2.1.284", started: 0)
        processes.put(201, "python3", parent: 200, started: 5)
        processes.register(200, writtenAt: 60)
        let watcher = try makeWatcher()
        watcher.activate()

        processes.drop(200)
        watcher.sweep()

        XCTAssertEqual(watcher.findings.leftBehind.map(\.pid), [201])
        watcher.stop()
    }

    func testOneBannerPerSweepAndNoneTwiceForTheSameProcess() throws {
        startSession()
        processes.put(103, "vite", parent: 101, started: 6)
        let watcher = try makeWatcher()
        var announced: [Int] = []
        watcher.notify = { announced.append($0) }
        watcher.activate()

        endSession()
        watcher.sweep()
        watcher.sweep()

        XCTAssertEqual(announced, [2])
        watcher.stop()
    }

    func testTheBannerCanBeSwitchedOffAndTheListStillFills() throws {
        startSession()
        let watcher = try makeWatcher()
        var announced = 0
        watcher.notify = { _ in announced += 1 }
        watcher.rules.notifies = false
        watcher.activate()

        endSession()
        watcher.sweep()

        XCTAssertEqual(announced, 0)
        XCTAssertEqual(watcher.findings.leftBehind.count, 1)
        watcher.stop()
    }

    func testIgnoringANameTakesItOffTheListAtOnce() throws {
        startSession()
        let watcher = try makeWatcher()
        watcher.activate()
        endSession()
        watcher.sweep()

        watcher.ignore("node")

        XCTAssertTrue(watcher.findings.leftBehind.isEmpty)
        XCTAssertEqual(OrphanRules.load(from: try XCTUnwrap(defaults)).ignored, ["node"])
        XCTAssertTrue(lines.contains { $0.hasPrefix("orphans rules") && $0.hasSuffix("ignored=1") })
        watcher.unignore("node")
        XCTAssertEqual(watcher.findings.leftBehind.count, 1)
        watcher.stop()
    }

    func testAnUnreadableTableLeavesTheListAsItWas() throws {
        startSession()
        let watcher = try makeWatcher()
        watcher.activate()
        endSession()
        watcher.sweep()

        processes.makeReadable(false)
        watcher.sweep()

        XCTAssertEqual(watcher.findings.leftBehind.count, 1)
        watcher.stop()
    }

    func testAnAgentSwitchedOffInAgentsIsNotFollowed() throws {
        startSession()
        let watcher = try makeWatcher()
        watcher.agentIsOn = { $0 != .claude }
        watcher.activate()

        endSession()
        watcher.sweep()

        XCTAssertEqual(watcher.findings.roots, 0)
        XCTAssertTrue(watcher.findings.isEmpty)
        XCTAssertEqual(watcher.agentsLeftAlone, [.claude])
        watcher.stop()
    }

    func testStoppingLetsGoOfEverything() throws {
        startSession()
        let watcher = try makeWatcher()
        watcher.activate()
        endSession()
        watcher.sweep()
        let reads = processes.reads

        watcher.stop()
        watcher.sweep()

        XCTAssertFalse(watcher.isRunning)
        XCTAssertTrue(watcher.findings.isEmpty)
        XCTAssertEqual(processes.reads, reads, "looked after being switched off")
    }

    func testForgettingEverythingLeavesNoKeyBehind() throws {
        let store = try XCTUnwrap(defaults)
        let watcher = try makeWatcher()
        watcher.ignore("node")
        watcher.rules.spinningPercent = 80
        XCTAssertNotNil(store.data(forKey: OrphanRules.defaultsKey))

        watcher.forgetEverything()

        XCTAssertNil(store.object(forKey: OrphanRules.defaultsKey))
        XCTAssertEqual(watcher.rules, OrphanRules())
        XCTAssertFalse(watcher.isRunning)
    }

    func testARuleSurvivesARelaunch() throws {
        let first = try makeWatcher()
        first.rules.spinningMinutes = 30
        first.ignore("node")

        let second = try makeWatcher()

        XCTAssertEqual(second.rules.spinningMinutes, 30)
        XCTAssertEqual(second.rules.ignored, ["node"])
    }

    /// The one test that reads the real table, and only this process in it.
    func testTheSystemTableListsThisProcessWithItsCpuTime() throws {
        let system = SystemProcesses.real
        let table = try XCTUnwrap(system.table())
        let me = try XCTUnwrap(table.first { $0.pid == getpid() })
        XCTAssertFalse(me.name.isEmpty)
        XCTAssertLessThan(abs(me.startedAt.timeIntervalSinceNow), 86_400 * 7)
        XCTAssertEqual(me.parent, getppid())

        var spent = 0.0
        let first = try XCTUnwrap(system.cpuSeconds(of: [getpid()])[getpid()])
        let until = Date().addingTimeInterval(0.3)
        while Date() < until { spent += 1 }
        let second = try XCTUnwrap(system.cpuSeconds(of: [getpid()])[getpid()])
        XCTAssertGreaterThan(spent, 0)
        // 0.3 s of spinning is about 0.3 s of CPU: seconds, not mach ticks.
        XCTAssertEqual(second - first, 0.3, accuracy: 0.25)
    }

    #if !BELAY_MAS
    func testEndingSendsTermAndLogsWhatWentAndWhatDid() async throws {
        startSession()
        processes.put(103, "vite", parent: 101, started: 6)
        processes.ignoreSignals(from: 103)
        let watcher = try makeWatcher()
        watcher.activate()
        endSession()
        watcher.sweep()

        await watcher.endAll()

        XCTAssertEqual(processes.signalled, [102, 103])
        XCTAssertEqual(watcher.notEnded, 1)
        XCTAssertEqual(watcher.findings.leftBehind.map(\.pid), [103])
        XCTAssertTrue(lines.contains("orphans ended=1 failed=1"))
        watcher.stop()
    }

    func testEndingOneLeavesTheOthersAlone() async throws {
        startSession()
        processes.put(103, "vite", parent: 101, started: 6)
        let watcher = try makeWatcher()
        watcher.activate()
        endSession()
        watcher.sweep()

        await watcher.end(OrphanWatcher.Target(pid: 103, startedAt: FakeProcesses.epoch + 6))

        XCTAssertEqual(processes.signalled, [103])
        XCTAssertEqual(watcher.findings.leftBehind.map(\.pid), [102])
        watcher.stop()
    }

    func testAPidThatBelongsToSomethingElseNowIsNotSignalled() async throws {
        startSession()
        let watcher = try makeWatcher()
        watcher.activate()
        endSession()
        watcher.sweep()
        processes.put(102, "Safari", started: 9_000)

        await watcher.end(OrphanWatcher.Target(pid: 102, startedAt: FakeProcesses.epoch + 5))

        XCTAssertTrue(processes.signalled.isEmpty)
        watcher.stop()
    }
    #endif
}
