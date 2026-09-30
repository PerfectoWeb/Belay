import Foundation

/// One file the system marked as a screen capture.
public struct ScreenshotCandidate: Equatable, Sendable {
    public let url: URL
    public let created: Date
    public let modified: Date
    public let isRecording: Bool
    public let isTagged: Bool

    public init(url: URL, created: Date, modified: Date, isRecording: Bool, isTagged: Bool) {
        self.url = url
        self.created = created
        self.modified = modified
        self.isRecording = isRecording
        self.isTagged = isTagged
    }
}

/// Which screenshots are due for the Trash. Pure: the clock and the files are
/// handed in.
public enum ScreenshotSweep {
    /// macOS writes a screenshot once, so its two dates agree to the second. A
    /// modification later than this is somebody opening the file and saving it.
    static let editSlack: TimeInterval = 5

    /// `notBefore` is when the cleaner was switched on. Nothing is older than
    /// that as far as an automatic pass is concerned: a desktop that held forty
    /// screenshots before the module arrived keeps them for one full age, so
    /// installing it never empties a desk in the same second. A pass the user
    /// asked for by name hands in `nil` and means what it says.
    public static func due(
        _ candidates: [ScreenshotCandidate],
        rules: ScreenshotRules,
        now: Date,
        notBefore: Date? = nil
    ) -> [ScreenshotCandidate] {
        candidates.filter { isDue($0, rules: rules, now: now, notBefore: notBefore) }
    }

    /// What a pass makes of one file.
    enum Verdict: Equatable {
        case due
        /// Protected by the rules: a recording, a tag, an edit.
        case kept
        /// Not old enough yet.
        case waiting
    }

    static func isDue(
        _ candidate: ScreenshotCandidate, rules: ScreenshotRules, now: Date, notBefore: Date?
    ) -> Bool {
        verdict(on: candidate, rules: rules, now: now, notBefore: notBefore) == .due
    }

    static func verdict(
        on candidate: ScreenshotCandidate, rules: ScreenshotRules, now: Date, notBefore: Date?
    ) -> Verdict {
        if candidate.isRecording && !rules.includesRecordings { return .kept }
        if rules.keepsTouched && (candidate.isTagged || wasEdited(candidate)) { return .kept }
        // Measured from the later date when edits are not protected, so a file
        // saved a minute ago is never swept for having been created yesterday.
        var reference = max(candidate.created, candidate.modified)
        if let notBefore { reference = max(reference, notBefore) }
        return now.timeIntervalSince(reference) >= rules.age ? .due : .waiting
    }

    static func wasEdited(_ candidate: ScreenshotCandidate) -> Bool {
        candidate.modified.timeIntervalSince(candidate.created) > editSlack
    }
}

/// What one pass over the folders did.
public struct SweepReport: Equatable, Sendable {
    public var trashed = 0
    public var failed = 0
    /// Why the first refusal happened, as an error domain and code and never
    /// a path: a pass that fails the same way every time has to be able to say
    /// how, or the log holds a count nobody can act on.
    public var firstFailure: String?
    /// Folders that could not be listed at all: gone, or access withdrawn.
    public var unreadable: [URL] = []
    /// Screenshots the rules protect, and screenshots not old enough yet. A
    /// report of "it did not take mine" is answered by these two numbers.
    public var kept = 0
    public var waiting = 0

    public init() {}
}

/// One pass: list each folder, pick what is due, move it to the Trash.
///
/// The two things that touch the disk are closures so a test can run a pass
/// without a disk, and so the app can wrap each in the folder's access scope.
public struct ScreenshotSweeper: Sendable {
    public var list: @Sendable (URL) throws -> [ScreenshotCandidate]
    public var trash: @Sendable (URL) throws -> Void

    public init(
        list: @escaping @Sendable (URL) throws -> [ScreenshotCandidate],
        trash: @escaping @Sendable (URL) throws -> Void
    ) {
        self.list = list
        self.trash = trash
    }

    public func run(rules: ScreenshotRules, now: Date, notBefore: Date? = nil) -> SweepReport {
        var report = SweepReport()
        for path in rules.folders {
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            guard let candidates = try? list(folder) else {
                report.unreadable.append(folder)
                continue
            }
            for candidate in candidates {
                let verdict = ScreenshotSweep.verdict(
                    on: candidate, rules: rules, now: now, notBefore: notBefore)
                guard verdict == .due else {
                    if verdict == .kept { report.kept += 1 } else { report.waiting += 1 }
                    continue
                }
                do {
                    try trash(candidate.url)
                    report.trashed += 1
                } catch {
                    report.failed += 1
                    if report.firstFailure == nil { report.firstFailure = Self.reason(error) }
                }
            }
        }
        return report
    }

    static func reason(_ error: Error) -> String {
        let error = error as NSError
        var reason = "\(error.domain):\(error.code)"
        if let under = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            reason += "/\(under.domain):\(under.code)"
        }
        return reason
    }
}
