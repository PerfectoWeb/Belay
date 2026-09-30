import Foundation
import Testing

@testable import BelayModules

@Suite("Module ledger")
struct ModuleLedgerTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test("Installing switches the module on")
    func installEnables() {
        var ledger = ModuleLedger()
        #expect(!ledger.isInstalled(.screenshotCleaner))

        ledger.install(.screenshotCleaner, at: now)

        #expect(ledger.isInstalled(.screenshotCleaner))
        #expect(ledger.isEnabled(.screenshotCleaner))
    }

    @Test("Switching off keeps the module installed")
    func disableKeepsInstalled() {
        var ledger = ModuleLedger()
        ledger.install(.screenshotCleaner, at: now)

        ledger.setEnabled(false, for: .screenshotCleaner)

        #expect(ledger.isInstalled(.screenshotCleaner))
        #expect(!ledger.isEnabled(.screenshotCleaner))
    }

    @Test("A switch cannot install a module that is not there")
    func enableWithoutInstall() {
        var ledger = ModuleLedger()

        ledger.setEnabled(true, for: .screenshotCleaner)

        #expect(!ledger.isInstalled(.screenshotCleaner))
        #expect(!ledger.isEnabled(.screenshotCleaner))
    }

    @Test("Installing again keeps the first date")
    func reinstallKeepsDate() {
        var ledger = ModuleLedger()
        ledger.install(.screenshotCleaner, at: now)
        ledger.setEnabled(false, for: .screenshotCleaner)

        ledger.install(.screenshotCleaner, at: now.addingTimeInterval(3600))

        #expect(ledger.records[ModuleID.screenshotCleaner.rawValue]?.installedAt == now)
        #expect(ledger.isEnabled(.screenshotCleaner))
    }

    @Test("The ledger survives a relaunch, unknown modules included")
    func roundTrip() throws {
        let scratch = try Scratch()
        defer { scratch.discard() }
        var ledger = ModuleLedger()
        ledger.install(.screenshotCleaner, at: now)
        ledger.install(ModuleID(rawValue: "from-a-newer-belay"), at: now)
        ledger.save(to: scratch.defaults)

        let reloaded = ModuleLedger(defaults: try scratch.reopened())

        #expect(reloaded == ledger)
    }

    @Test("Removing the last module leaves no key behind")
    func removeClearsKey() throws {
        let scratch = try Scratch()
        defer { scratch.discard() }
        var ledger = ModuleLedger()
        ledger.install(.screenshotCleaner, at: now)
        ledger.save(to: scratch.defaults)

        ledger.remove(.screenshotCleaner)
        ledger.save(to: scratch.defaults)

        #expect(scratch.defaults.object(forKey: ModuleLedger.defaultsKey) == nil)
    }

    @Test("A ledger that does not decode is an empty one")
    func damagedLedger() throws {
        let scratch = try Scratch()
        defer { scratch.discard() }
        scratch.defaults.set(Data("not json".utf8), forKey: ModuleLedger.defaultsKey)

        #expect(ModuleLedger(defaults: scratch.defaults).records.isEmpty)
    }
}

/// A throwaway preferences suite, removed when the test ends, so nothing here
/// reaches the domain the installed app reads.
struct Scratch {
    let name = "com.perfectoweb.belay.tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: name))
    }

    func reopened() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: name))
    }

    func discard() {
        defaults.removePersistentDomain(forName: name)
        defaults.synchronize()
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Preferences/\(name).plist")
        try? FileManager.default.removeItem(at: url)
    }
}
