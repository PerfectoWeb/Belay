import OSLog

/// Logging surface for every Vigil module.
///
/// Categories map one-to-one onto modules so a `log stream` filter is useful
/// without knowing the code. Never log transcript content, prompts, user file
/// paths or session identifiers at the default level — session IDs go through
/// `%{private}@`. See docs/02 and SECURITY.md.
public enum Log {
    public static let subsystem = "com.perfecto-web.vigil"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let core = Logger(subsystem: subsystem, category: "core")
    public static let power = Logger(subsystem: subsystem, category: "power")
    public static let providers = Logger(subsystem: subsystem, category: "providers")
    public static let bridge = Logger(subsystem: subsystem, category: "bridge")
    public static let settings = Logger(subsystem: subsystem, category: "settings")

    public static let signposter = OSSignposter(subsystem: subsystem, category: "performance")
}
