import BelaySupport
import Foundation

/// The sandbox before a grant: nothing is readable, and nothing can be said
/// to be missing either. What `DirectFileAccess` can never be — it always
/// knows whether a folder exists — and what the availability tests need to
/// reach the "needs setup" answer honestly.
struct DeniedFileAccess: FileAccessProvider {
    func hasAccess(to url: URL) -> Bool { false }
    func withAccess<T>(to url: URL, _ body: (URL) throws -> T) throws -> T {
        throw FileAccessError.accessDenied(url)
    }
}
