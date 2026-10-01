import Foundation

/// How the nudge is set up.
public struct NudgeRules: Codable, Equatable, Sendable {
    public static let defaultsKey = "BelayNudge"

    /// Minutes between two reminders while an agent keeps waiting. Zero is
    /// "never remind".
    public static let repeatMinutes = [0, 2, 5, 10, 15]
    public static let repeatCounts = [1, 3, 5, 10]
    /// Runs shorter than these are not worth a sound or a banner.
    public static let minimumRuns = [10, 30, 60, 300]

    public static let defaultRepeatMinutes = 5
    public static let defaultRepeatAtMost = 3
    public static let defaultMinimumRun = 30

    public var finishedSound: Bool
    public var waitingSound: Bool
    public var quietSound: Bool
    /// A banner naming the workspace when a run ends.
    public var namesFinished: Bool
    public var repeatAfterMinutes: Int
    public var repeatAtMost: Int
    public var minimumRunSeconds: Int

    public init(
        finishedSound: Bool = true,
        waitingSound: Bool = true,
        quietSound: Bool = true,
        namesFinished: Bool = true,
        repeatAfterMinutes: Int = NudgeRules.defaultRepeatMinutes,
        repeatAtMost: Int = NudgeRules.defaultRepeatAtMost,
        minimumRunSeconds: Int = NudgeRules.defaultMinimumRun
    ) {
        self.finishedSound = finishedSound
        self.waitingSound = waitingSound
        self.quietSound = quietSound
        self.namesFinished = namesFinished
        self.repeatAfterMinutes =
            Self.repeatMinutes.contains(repeatAfterMinutes)
            ? repeatAfterMinutes : Self.defaultRepeatMinutes
        self.repeatAtMost =
            Self.repeatCounts.contains(repeatAtMost) ? repeatAtMost : Self.defaultRepeatAtMost
        self.minimumRunSeconds =
            Self.minimumRuns.contains(minimumRunSeconds)
            ? minimumRunSeconds : Self.defaultMinimumRun
    }

    /// A field that is missing, or that a newer build wrote in a shape this
    /// one does not know, takes its default: a record must never reset what
    /// the person did choose.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func flag(_ key: CodingKeys) -> Bool {
            (try? values.decodeIfPresent(Bool.self, forKey: key)) ?? true
        }
        func number(_ key: CodingKeys, _ fallback: Int) -> Int {
            (try? values.decodeIfPresent(Int.self, forKey: key)) ?? fallback
        }
        self.init(
            finishedSound: flag(.finishedSound),
            waitingSound: flag(.waitingSound),
            quietSound: flag(.quietSound),
            namesFinished: flag(.namesFinished),
            repeatAfterMinutes: number(.repeatAfterMinutes, Self.defaultRepeatMinutes),
            repeatAtMost: number(.repeatAtMost, Self.defaultRepeatAtMost),
            minimumRunSeconds: number(.minimumRunSeconds, Self.defaultMinimumRun))
    }

    public static func load(from defaults: UserDefaults) -> NudgeRules {
        guard let data = defaults.data(forKey: defaultsKey),
            let rules = try? JSONDecoder().decode(NudgeRules.self, from: data)
        else { return NudgeRules() }
        return rules
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }
}
