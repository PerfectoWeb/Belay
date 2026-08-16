import Foundation

/// A marketing version, compared the way a person would read it.
///
/// String comparison is wrong here and wrong quietly: `"1.10.0" < "1.9.0"` is
/// true for strings, which would show somebody the release notes for a version
/// they already have, or skip the ones they have not seen. This is the whole
/// reason the type exists.
///
/// Anything unparseable is `nil` rather than a zero version. A build whose
/// `CFBundleShortVersionString` is not a version number is a build that should
/// not be making decisions about what to show; the caller shows nothing.
struct AppVersion: Comparable, Equatable, CustomStringConvertible {
    let parts: [Int]

    /// Accepts one to four components, which covers everything this project
    /// ships and everything it plausibly might: `1`, `1.2`, `1.2.3`, `1.2.3.4`.
    /// A missing component is zero, so `1.2` and `1.2.0` are the same version
    /// and neither is newer than the other.
    init?(_ raw: String?) {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let fields = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(fields.count) else { return nil }

        var parsed: [Int] = []
        for field in fields {
            // `Int(field)` alone accepts a leading "+" and "-", which would make
            // "1.-2.0" a version. Digits only.
            guard !field.isEmpty, field.allSatisfy(\.isNumber), let value = Int(field) else {
                return nil
            }
            parsed.append(value)
        }
        parts = parsed
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    /// Trailing zeros are kept, so a version prints as it was written.
    var description: String { parts.map(String.init).joined(separator: ".") }
}
