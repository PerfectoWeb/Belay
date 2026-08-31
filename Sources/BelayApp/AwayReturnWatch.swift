import BelaySupport
import Foundation

/// What the user missed, told once, when they come back.
///
/// Every competitor that notifies does it turn by turn; the moment nobody else
/// owns is the *return*. One banner — "Belay kept your Mac awake for 2h 14m;
/// 3 runs finished" — says the whole absence at once, using only numbers the
/// statistics already earn: time held while away (`AwayTime`'s definition, so
/// the claim stays honest) and finishes the trigger already announces.
///
/// Pure, like `AnnouncementTrigger`, so the "when" is testable without a
/// clock or a notification centre. `AwayReturnWatch` below owns the timer.
struct AwaySummary: Equatable {
    struct Report: Equatable {
        var heldAway: TimeInterval
        var finishedRuns: Int
        /// The worst `ProcessInfo.ThermalState` seen while away, as its raw
        /// severity (0 nominal … 3 critical). Words, not degrees: the real
        /// temperature lives behind SMC keys that change with every chip,
        /// and the summary must never be a guess dressed as a measurement.
        var peakThermal: Int = 0
    }

    /// Under this, nothing was at risk and the banner would be noise.
    static let minimumHeld: TimeInterval = 5 * 60

    private var away = false
    private var heldAway: TimeInterval = 0
    private var finishedRuns = 0
    private var peakThermal = 0
    private var lastTick: Date?

    /// Whether anything is being accumulated or waited for. The watch uses
    /// this to stop its timer the moment there is nothing left to observe.
    var isObserving: Bool { away }

    /// A run finished. Counted only while the user is away — a finish they
    /// watched happen needs no retelling.
    mutating func noteFinished() {
        guard away else { return }
        finishedRuns += 1
    }

    /// One observation of the world; returns a report exactly once, on the
    /// tick where the user turns out to be back.
    mutating func tick(
        idle: TimeInterval, holding: Bool, thermal: Int = 0, now: Date
    ) -> Report? {
        defer { lastTick = now }
        let isAway = AwayTime.isAway(idle)

        if away { peakThermal = max(peakThermal, thermal) }

        if away, !isAway {
            // The return. Say it or drop it, then start clean either way.
            let report = Report(
                heldAway: heldAway, finishedRuns: finishedRuns, peakThermal: peakThermal)
            away = false
            heldAway = 0
            finishedRuns = 0
            peakThermal = 0
            guard report.heldAway >= Self.minimumHeld else { return nil }
            return report
        }

        if !away, isAway {
            away = true
            heldAway = 0
            finishedRuns = 0
            peakThermal = thermal
            return nil
        }

        // Same honesty rule as `UsageRecorder`: a slice counts only when the
        // user was away for the whole of it, so a return mid-slice does not
        // inflate the number the banner is about to claim.
        if away, holding, let lastTick {
            let elapsed = now.timeIntervalSince(lastTick)
            if elapsed > 0, idle >= elapsed {
                heldAway += elapsed
            }
        }
        return nil
    }
}

/// Owns the timer around `AwaySummary`, the same shape as `UsageRecorder`'s
/// sampler: nothing is scheduled while there is nothing to measure. The timer
/// starts when a hold and an absence overlap, and stops the moment the
/// summary has either fired or lost its reason to.
@MainActor
final class AwayReturnWatch {
    private var summary = AwaySummary()
    private var holding = false
    private var sampler: Timer?
    private let onReport: (AwaySummary.Report) -> Void

    private let sampleInterval: TimeInterval = 30

    init(onReport: @escaping (AwaySummary.Report) -> Void) {
        self.onReport = onReport
    }

    /// Fed from the controller's snapshot handler, so the watch always knows
    /// whether a hold is on without a query path of its own.
    func update(holdingSince: Date?, now: Date = Date()) {
        holding = holdingSince != nil
        tick(now: now)
    }

    func noteFinished() {
        summary.noteFinished()
    }

    private func tick(now: Date) {
        let idle = AwayTime.secondsSinceInput()
        let thermal = Self.severity(ProcessInfo.processInfo.thermalState)
        if let report = summary.tick(idle: idle, holding: holding, thermal: thermal, now: now) {
            Diagnostics.note(
                "away summary held=\(Int(report.heldAway))s finished=\(report.finishedRuns)")
            onReport(report)
        }
        // The timer's whole job is catching the return after snapshots have
        // gone quiet; while nobody is away there is nothing to catch.
        if summary.isObserving {
            startSampling()
        } else {
            sampler?.invalidate()
            sampler = nil
        }
    }

    static func severity(_ state: ProcessInfo.ThermalState) -> Int {
        switch state {
        case .nominal: return 0
        case .fair: return 1
        case .serious: return 2
        case .critical: return 3
        @unknown default: return 3
        }
    }

    private func startSampling() {
        guard sampler == nil else { return }
        let timer = Timer(timeInterval: sampleInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(now: Date()) }
        }
        timer.tolerance = sampleInterval / 4
        RunLoop.main.add(timer, forMode: .common)
        sampler = timer
    }

    deinit {
        MainActor.assumeIsolated { sampler?.invalidate() }
    }
}
