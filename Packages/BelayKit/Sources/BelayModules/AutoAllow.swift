import Foundation

/// How the automatic approval is set up.
public struct AutoAllowRules: Codable, Equatable, Sendable {
    public static let defaultsKey = "BelayAutoAllow"

    public enum Scope: String, Codable, Sendable, CaseIterable {
        /// Only a request that names a site on this Mac or this network.
        case localSites
        /// Whatever is asked.
        case everything
    }

    /// An app whose requests are answered: every one whose agent is switched
    /// on in Agents.
    public enum App: String, Codable, Sendable, CaseIterable {
        case claude
        case codex
    }

    /// How long it stays on once switched on, in seconds. Zero is "until I
    /// switch it off".
    public static let durations: [TimeInterval] = [1, 4, 8, 0].map { $0 * 3600 }
    public static let defaultDuration: TimeInterval = 4 * 3600

    public var scope: Scope
    public var duration: TimeInterval
    /// Whether a session that waits behind the window is brought into it,
    /// answered, and the window put back.
    public var reachesBehind: Bool

    public init(
        scope: Scope = .localSites,
        duration: TimeInterval = AutoAllowRules.defaultDuration,
        reachesBehind: Bool = false
    ) {
        self.scope = scope
        self.duration = Self.durations.contains(duration) ? duration : Self.defaultDuration
        self.reachesBehind = reachesBehind
    }

    /// A scope this build has never heard of falls back to the narrow one: a
    /// damaged record must not widen what gets approved.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let scope = try? values.decodeIfPresent(Scope.self, forKey: .scope)
        let duration = try? values.decodeIfPresent(TimeInterval.self, forKey: .duration)
        let reachesBehind = try? values.decodeIfPresent(Bool.self, forKey: .reachesBehind)
        self.init(
            scope: scope ?? .localSites,
            duration: duration ?? Self.defaultDuration,
            reachesBehind: reachesBehind ?? false)
    }

    public static func load(from defaults: UserDefaults) -> AutoAllowRules {
        guard let data = defaults.data(forKey: defaultsKey),
            let rules = try? JSONDecoder().decode(AutoAllowRules.self, from: data)
        else { return AutoAllowRules() }
        return rules
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }

    /// When a switch flipped at `start` runs out, or nil when it does not.
    public func deadline(from start: Date) -> Date? {
        duration > 0 ? start.addingTimeInterval(duration) : nil
    }
}

/// A request for permission as it stands on the screen: the words around the
/// button, in reading order.
public struct PermissionPrompt: Equatable, Sendable {
    public var texts: [String]
    /// The site the request is about, where the app marks it out itself: a
    /// link in the question. Empty when such an app marked none. Nil where
    /// the site has to be found among the words.
    public var site: String?

    public init(texts: [String], site: String? = nil) {
        self.texts = texts
        self.site = site
    }

    /// The site a request to act on a site is about. Where the app does not
    /// mark it out, such a request shows what it asks as a record that names
    /// the origin, beside whatever the action needs: which element, which
    /// text. A request to run a command names no origin, even when the
    /// command mentions a site.
    public var origin: String? {
        // An app that marks the site is taken at its mark alone: there the
        // words are the agent's own, and a record among them proves nothing.
        if let site { return LocalSite.hosts(in: site).first }
        for text in texts {
            guard let record = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
                let fields = record as? [String: Any],
                let origin = fields["origin"] as? String,
                let host = LocalSite.hosts(in: origin).first
            else { continue }
            return host
        }
        return nil
    }

    /// Every site the request names.
    public var hosts: [String] {
        var found: [String] = []
        for text in texts {
            for host in LocalSite.hosts(in: text) where !found.contains(host) {
                found.append(host)
            }
        }
        return found
    }
}

public enum AutoAllowDecision {
    /// Under the narrow scope a request is approved only when it asks to
    /// act on a site, that site is local, and so is every other site it
    /// names. Anything else is left for the person: a command to run, a file
    /// to write, a request that names nothing.
    public static func approves(_ prompt: PermissionPrompt, rules: AutoAllowRules) -> Bool {
        switch rules.scope {
        case .everything:
            return true
        case .localSites:
            guard let origin = prompt.origin, LocalSite.isLocal(host: origin) else { return false }
            return prompt.hosts.allSatisfy(LocalSite.isLocal(host:))
        }
    }

    /// What the log says was approved: the site, never the words around it.
    public static func subject(of prompt: PermissionPrompt) -> String {
        prompt.origin ?? prompt.hosts.joined(separator: ", ")
    }
}

/// The approvals Belay gave, newest first, so the user can see what was
/// answered in their name.
public struct AutoAllowLog: Codable, Equatable, Sendable {
    public static let defaultsKey = "BelayAutoAllowLog"
    public static let capacity = 50

    public struct Entry: Codable, Equatable, Sendable, Identifiable {
        public var id: Date { date }
        public let date: Date
        /// The sites the request named; empty when it named none.
        public let subject: String

        public init(date: Date, subject: String) {
            self.date = date
            self.subject = subject
        }
    }

    public private(set) var entries: [Entry]
    public private(set) var total: Int

    public init(entries: [Entry] = [], total: Int = 0) {
        self.entries = entries
        self.total = total
    }

    public mutating func record(_ subject: String, at date: Date) {
        entries.insert(Entry(date: date, subject: subject), at: 0)
        if entries.count > Self.capacity { entries.removeLast(entries.count - Self.capacity) }
        total += 1
    }

    public static func load(from defaults: UserDefaults) -> AutoAllowLog {
        guard let data = defaults.data(forKey: defaultsKey),
            let log = try? JSONDecoder().decode(AutoAllowLog.self, from: data)
        else { return AutoAllowLog() }
        return log
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }
}
