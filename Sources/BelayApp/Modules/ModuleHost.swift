import BelayModules
import Foundation
import Observation

/// What the Modules pane is showing: the search, the filter and the card that
/// is open.
///
/// Kept outside the view because the Settings window measures a pane by
/// building a second copy of it, and a copy starts with fresh `@State`: the
/// window would size itself to a list nobody is looking at.
@MainActor
@Observable
final class ModuleBrowsing {
    enum Scope: Hashable {
        case all
        case installed
    }

    var query = ""
    var scope: Scope = .all
    var expanded: ModuleID?
}

/// Owns the modules: which are installed, and the running half of each.
@MainActor
@Observable
final class ModuleHost {
    private(set) var ledger: ModuleLedger
    let screenshots: ScreenshotCleaner
    let microphone: MicKeepWarm
    let autoAllow: AutoAllower
    let nudge: Nudger
    let orphans: OrphanWatcher
    let browsing = ModuleBrowsing()

    @ObservationIgnored private let defaults: UserDefaults

    /// Where the screenshot cleaner starts when nobody picked a folder.
    @ObservationIgnored private let captureFolder: () -> URL

    init(
        defaults: UserDefaults = .standard,
        screenshots: ScreenshotCleaner? = nil,
        microphone: MicKeepWarm? = nil,
        autoAllow: AutoAllower? = nil,
        nudge: Nudger? = nil,
        orphans: OrphanWatcher? = nil,
        captureFolder: @escaping () -> URL = { ScreenshotFolderAccess.systemFolder }
    ) {
        self.defaults = defaults
        self.captureFolder = captureFolder
        ledger = ModuleLedger(defaults: defaults)
        self.screenshots = screenshots ?? ScreenshotCleaner(defaults: defaults)
        self.microphone = microphone ?? MicKeepWarm(defaults: defaults)
        self.autoAllow = autoAllow ?? AutoAllower(defaults: defaults)
        self.nudge = nudge ?? Nudger(defaults: defaults)
        self.orphans = orphans ?? OrphanWatcher(defaults: defaults)
        self.autoAllow.onExpired = { [weak self] in self?.setEnabled(false, for: .autoAllow) }
    }

    /// Starts whatever was left switched on. Called once, at launch.
    func start() {
        let offered = ModuleDescriptor.offered().map(\.id)
        // What a report needs first: a log that starts mid-run says nothing
        // of what was switched on before it.
        let names = { (ids: [ModuleID]) in
            ids.isEmpty ? "none" : ids.map(\.rawValue).joined(separator: ",")
        }
        Diagnostics.note(
            """
            modules start installed=\(names(offered.filter(ledger.isInstalled))) \
            on=\(names(offered.filter(ledger.isEnabled)))
            """)
        for id in offered where ledger.isEnabled(id) {
            run(id)
        }
    }

    func stop() {
        screenshots.stop()
        microphone.stop()
        autoAllow.stop()
        nudge.stop()
        orphans.stop()
        ScreenshotFolderAccess.relinquish()
    }

    /// `folder` is what the user picked where the build has to ask; elsewhere
    /// the screenshot cleaner starts on the folder macOS saves captures to.
    func install(_ id: ModuleID, folder: URL? = nil) {
        if id == .screenshotCleaner, screenshots.rules.folders.isEmpty {
            screenshots.add(folder: folder ?? captureFolder())
        }
        ledger.install(id, at: Date())
        ledger.save(to: defaults)
        Diagnostics.note("module install id=\(id.rawValue)")
        activate(id)
    }

    func remove(_ id: ModuleID) {
        switch id {
        case .screenshotCleaner: screenshots.forgetEverything()
        case .micKeepWarm: microphone.forgetEverything()
        case .autoAllow: autoAllow.forgetEverything()
        case .nudge: nudge.forgetEverything()
        case .orphanWatch: orphans.forgetEverything()
        default: break
        }
        ledger.remove(id)
        ledger.save(to: defaults)
        if browsing.expanded == id { browsing.expanded = nil }
        Diagnostics.note("module remove id=\(id.rawValue)")
    }

    func setEnabled(_ isEnabled: Bool, for id: ModuleID) {
        guard ledger.isInstalled(id), ledger.isEnabled(id) != isEnabled else { return }
        ledger.setEnabled(isEnabled, for: id)
        ledger.save(to: defaults)
        Diagnostics.note("module \(isEnabled ? "on" : "off") id=\(id.rawValue)")
        if isEnabled { activate(id) } else { halt(id) }
    }

    /// Launch: whatever was on carries on as it was.
    private func run(_ id: ModuleID) {
        switch id {
        case .screenshotCleaner: screenshots.start()
        case .micKeepWarm: microphone.start()
        case .autoAllow: autoAllow.start()
        case .nudge: nudge.start()
        case .orphanWatch: orphans.start()
        default: break
        }
    }

    /// The user switched it on just now.
    private func activate(_ id: ModuleID) {
        switch id {
        case .screenshotCleaner: screenshots.activate()
        case .micKeepWarm: microphone.activate()
        case .autoAllow: autoAllow.activate()
        case .nudge: nudge.activate()
        case .orphanWatch: orphans.activate()
        default: break
        }
    }

    private func halt(_ id: ModuleID) {
        switch id {
        case .screenshotCleaner: screenshots.stop()
        case .micKeepWarm: microphone.stop()
        case .autoAllow: autoAllow.deactivate()
        case .nudge: nudge.stop()
        case .orphanWatch: orphans.stop()
        default: break
        }
    }

    /// The list as the pane shows it, after the filter and the search.
    var shown: [ModuleDescriptor] {
        ModuleDescriptor.offered().filter { module in
            let inScope = browsing.scope == .all || ledger.isInstalled(module.id)
            return inScope && ModuleSearch.matches(browsing.query, in: module.searchable)
        }
    }
}
