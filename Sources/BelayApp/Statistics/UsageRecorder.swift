import Foundation

/// Turns a sequence of holds into statistics.
///
/// Samples only while an assertion is held. Nothing is scheduled when Belay is
/// idle, which is the same rule the menu bar animation follows and the reason
/// the idle budget survives.
@MainActor
final class UsageRecorder {
    private let store: UsageStatisticsStore
    private(set) var statistics: UsageStatistics

    private var holdStarted: Date?
    private var awayInCurrentHold: TimeInterval = 0
    private var lastSample: Date?
    private var sampler: Timer?

    /// Frequent enough that a coffee break is measured to the minute, rare
    /// enough to be free.
    private let sampleInterval: TimeInterval = 30

    init(store: UsageStatisticsStore = UsageStatisticsStore()) {
        self.store = store
        statistics = store.load()
    }

    /// Throws away every recorded number and starts again from now.
    ///
    /// The hold in progress is dropped with the rest rather than banked into
    /// the empty record: a reset that immediately writes back the run you were
    /// in the middle of is not a reset, and the run was already counted in what
    /// was just discarded.
    func reset(now: Date = Date()) {
        holdStarted = nil
        awayInCurrentHold = 0
        lastSample = nil
        statistics = UsageStatistics()
        store.save(statistics)
    }

    /// Called with the coordinator's `holdingSince` on every snapshot.
    func update(holdingSince: Date?, now: Date = Date()) {
        switch (holdStarted, holdingSince) {
        case (nil, let started?):
            begin(at: started, now: now)
        case (let previous?, nil):
            finish(startedAt: previous, now: now)
        case (let previous?, let started?) where previous != started:
            // A new hold began without us seeing the gap; bank the old one.
            finish(startedAt: previous, now: started)
            begin(at: started, now: now)
        default:
            sample(now: now)
        }
    }

    /// Ends the current hold and writes it out. Called on quit, so a run that
    /// was still going when the user left is not lost.
    func flush(now: Date = Date()) {
        guard let holdStarted else { return }
        finish(startedAt: holdStarted, now: now)
    }

    private func begin(at started: Date, now: Date) {
        holdStarted = started
        awayInCurrentHold = 0
        lastSample = now
        startSampling()
    }

    private func finish(startedAt: Date, now: Date) {
        sample(now: now)
        let duration = now.timeIntervalSince(startedAt)
        statistics.record(hold: duration, away: awayInCurrentHold, on: now)
        store.save(statistics)
        holdStarted = nil
        awayInCurrentHold = 0
        lastSample = nil
        sampler?.invalidate()
        sampler = nil
    }

    /// Credits the elapsed slice as unattended if the user was away for the
    /// whole of it. Attributing a slice the user was present for would inflate
    /// the one number the statistics are supposed to be honest about.
    private func sample(now: Date) {
        guard let lastSample else { return }
        let elapsed = now.timeIntervalSince(lastSample)
        guard elapsed > 0 else { return }
        self.lastSample = now
        let idle = AwayTime.secondsSinceInput()
        guard idle >= elapsed, AwayTime.isAway(idle) else { return }
        awayInCurrentHold += elapsed
    }

    private func startSampling() {
        sampler?.invalidate()
        let timer = Timer(timeInterval: sampleInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample(now: Date()) }
        }
        timer.tolerance = sampleInterval / 4
        RunLoop.main.add(timer, forMode: .common)
        sampler = timer
    }

    deinit {
        MainActor.assumeIsolated { sampler?.invalidate() }
    }
}
