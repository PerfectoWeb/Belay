import Foundation

/// How the screenshot cleaner is set up.
public struct ScreenshotRules: Codable, Equatable, Sendable {
    public static let defaultsKey = "BelayScreenshotCleaner"

    /// The ages offered in Settings, in seconds. A screenshot taken for an
    /// agent is read within minutes; an hour is already generous, and a week is
    /// for people who want the desk swept but not soon.
    public static let ages: [TimeInterval] = [1, 2, 4, 8, 24, 72, 168].map { $0 * 3600 }
    public static let defaultAge: TimeInterval = 4 * 3600

    /// How old a screenshot has to be before it goes to the Trash.
    public var age: TimeInterval
    /// Screen recordings carry the same mark as screenshots. Off by default:
    /// a recording is usually made to be kept.
    public var includesRecordings: Bool
    /// Leave alone anything the user tagged in Finder or edited afterwards.
    public var keepsTouched: Bool
    /// The folders swept, as paths.
    public var folders: [String]

    public init(
        age: TimeInterval = ScreenshotRules.defaultAge,
        includesRecordings: Bool = false,
        keepsTouched: Bool = true,
        folders: [String] = []
    ) {
        self.age = Self.nearestAge(to: age)
        self.includesRecordings = includesRecordings
        self.keepsTouched = keepsTouched
        self.folders = folders
    }

    /// Field by field, so a record written before a rule existed still loads
    /// and takes that rule's default.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            age: try values.decodeIfPresent(TimeInterval.self, forKey: .age) ?? Self.defaultAge,
            includesRecordings: try values.decodeIfPresent(Bool.self, forKey: .includesRecordings)
                ?? false,
            keepsTouched: try values.decodeIfPresent(Bool.self, forKey: .keepsTouched) ?? true,
            folders: try values.decodeIfPresent([String].self, forKey: .folders) ?? []
        )
    }

    /// A hand-edited or damaged value lands on the closest age the picker can
    /// show, so the control never opens on a choice it does not have.
    public static func nearestAge(to age: TimeInterval) -> TimeInterval {
        ages.min { abs($0 - age) < abs($1 - age) } ?? defaultAge
    }

    public static func load(from defaults: UserDefaults) -> ScreenshotRules {
        guard let data = defaults.data(forKey: defaultsKey),
            let rules = try? JSONDecoder().decode(ScreenshotRules.self, from: data)
        else { return ScreenshotRules() }
        return rules
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }
}
