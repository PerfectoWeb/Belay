import Foundation
import Testing

/// A throwaway preferences suite, one per test, removed when the test ends.
///
/// Every test in this target goes through here: a test that wrote into the real
/// `com.perfecto-web.belay` domain would change the behaviour of the installed
/// app on the machine running it.
struct ScratchDefaults {
    let name: String
    let defaults: UserDefaults

    init() throws {
        let name = "com.perfecto-web.belay.tests.\(UUID().uuidString)"
        self.name = name
        defaults = try #require(UserDefaults(suiteName: name))
    }

    /// A second handle on the same suite, so a re-created store proves values
    /// came back off disk rather than out of the previous object.
    func reopened() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: name))
    }

    func discard() {
        defaults.removePersistentDomain(forName: name)
        // Emptying the domain leaves the plist behind. It is ours, nothing else
        // will ever read it, and a test run should not litter ~/Library.
        //
        // The synchronize is what makes the removal stick: cfprefsd writes the
        // file lazily, so deleting it first only means it is rewritten, empty,
        // a moment later. Thousands of those had accumulated before anyone
        // looked in the folder.
        defaults.synchronize()
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Preferences/\(name).plist")
        try? FileManager.default.removeItem(at: url)
    }
}

func withScratchDefaults(_ body: (ScratchDefaults) throws -> Void) throws {
    let scratch = try ScratchDefaults()
    defer { scratch.discard() }
    try body(scratch)
}
