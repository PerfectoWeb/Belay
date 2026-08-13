import AppKit
import BelayProviders
import BelaySettings
import SwiftUI
import XCTest

@testable import Belay

/// The "Other tools" grid.
///
/// The Settings window is a fixed 700 pt and measures its panes to decide how
/// tall to be, so a grid that mis-measures does not look wrong — it makes the
/// window wrong. These tests hold the pane's width still at every count of tools
/// a user can plausibly reach, and check the tile keeps working for a target that
/// came from no preset at all.
@MainActor
final class GenericTargetGridTests: XCTestCase {
    private func targets(_ count: Int) -> [GenericTarget] {
        (0..<count).map { index in
            let preset = GenericPreset.all[index % GenericPreset.all.count]
            return GenericTarget(
                displayName: "\(preset.displayName) \(index)",
                watchedFolder: URL(fileURLWithPath: "/Users/someone/projects/repo-\(index)"),
                processName: preset.processName,
                webhookIdentifier: preset.id)
        }
    }

    private func paneSize(_ targets: [GenericTarget]) -> CGSize {
        let view = NSHostingView(
            rootView: SettingsStack { GenericTargetsSection(targets: .constant(targets)) })
        view.layoutSubtreeIfNeeded()
        return view.fittingSize
    }

    /// One tile at the width two of them get in the control column.
    private func tileSize(_ target: GenericTarget) -> CGSize {
        let width = (TargetTileMetrics.columnWidth - TargetTileMetrics.spacing) / 2
        let tile = GenericTargetTile(target: target, remove: { _ in })
        let view = NSHostingView(rootView: tile.frame(width: width))
        view.layoutSubtreeIfNeeded()
        return view.fittingSize
    }

    /// Proportion of inked pixels, the only way to tell a mark from a blank box.
    private func ink(_ image: NSImage) -> Double {
        guard
            let data = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: data)
        else { return 0 }
        var opaque = 0
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
                opaque += 1
            }
        }
        return Double(opaque) / Double(bitmap.pixelsWide * bitmap.pixelsHigh)
    }

    func testTheGridStaysInsideThePaneAtEveryCount() {
        for count in [0, 1, 4, 12] {
            let size = paneSize(targets(count))
            XCTAssertEqual(
                size.width, SettingsPane.width,
                "\(count) tools measured \(size.width) pt wide — the Settings window would resize")
            XCTAssertGreaterThan(size.height, 0, "\(count) tools produced a pane with no height")
        }
    }

    /// Two per row in the control column. One-up wasted half the column; three
    /// only fits across the whole pane, which breaks the label/control rhythm.
    func testToolsGoTwoToARow() {
        let one = paneSize(targets(1)).height
        XCTAssertEqual(paneSize(targets(2)).height, one, accuracy: 0.5, "the second tile wrapped")
        XCTAssertGreaterThan(paneSize(targets(3)).height, one, "the third tile did not wrap")
    }

    /// Twelve tools is six rows, and the grid grows downwards only.
    func testManyToolsGrowTheGridDownwards() {
        let one = paneSize(targets(1))
        let twelve = paneSize(targets(12))
        let row = paneSize(targets(3)).height - one.height
        XCTAssertGreaterThan(row, 0, "a second row took no extra height")
        XCTAssertEqual(twelve.width, one.width)
        XCTAssertEqual(
            twelve.height, one.height + 5 * row, accuracy: 0.5, "twelve tools is six rows of two")
    }

    /// The row is `[mark][name over detail]`, two lines tall. Three — the mark
    /// on a line of its own above them — is what made the list so heavy.
    func testTheRowIsTwoLinesTall() {
        let row = paneSize(targets(3)).height - paneSize(targets(1)).height
        XCTAssertLessThan(row, 60, "the row grew back to three lines")
        XCTAssertGreaterThan(row, 20, "the row collapsed")
    }

    /// A target the user configured by hand has no preset id. It still has to
    /// show something: a neutral mark, its name, and what is being watched.
    func testATargetWithNoPresetStillGetsAMarkAndAName() {
        let handRolled = GenericTarget(displayName: "My own tool", processName: "mytool")
        XCTAssertNil(handRolled.webhookIdentifier, "fixture assumption changed")

        let tile = GenericTargetTile(target: handRolled, remove: { _ in })
        XCTAssertEqual(tile.markPreset, GenericTargetTile.neutralMark)
        XCTAssertGreaterThan(
            ink(ProviderMark.image(preset: tile.markPreset, size: 64)), 0.01,
            "the fallback mark is blank — the tile shows an empty box")
        // Built the way the tile builds it, interpolation included: the key is
        // "process %@", so `String(localized: "process mytool")` is a different
        // key with no translation and would pass only on an English Mac.
        let ownProcess = "mytool"
        XCTAssertEqual(tile.detail, String(localized: "process \(ownProcess)"))

        // Same box as a preset tile: both rows are there, neither collapsed.
        let preset = GenericPreset.all[1].target()
        XCTAssertEqual(tileSize(handRolled).height, tileSize(preset).height, accuracy: 0.5)
        let presetProcess = "gemini"
        XCTAssertEqual(
            GenericTargetTile(target: preset, remove: { _ in }).detail,
            ".gemini · " + String(localized: "process \(presetProcess)"))
    }

    func testTheRemoveButtonFiresWithItsOwnTarget() {
        let all = targets(4)
        var removed: [GenericTarget] = []
        for target in all {
            GenericTargetTile(target: target, remove: { removed.append($0) }).removeAction()
        }
        XCTAssertEqual(removed, all)
    }

    /// Removal still goes through the section's binding, one target at a time.
    func testRemovingATileRemovesOnlyThatTarget() {
        let all = targets(3)
        let box = TargetBox(all)
        let section = GenericTargetsSection(
            targets: Binding(get: { box.targets }, set: { box.targets = $0 }))

        section.remove(all[1])
        XCTAssertEqual(box.targets, [all[0], all[2]])

        section.remove(all[1])
        XCTAssertEqual(box.targets, [all[0], all[2]], "removing a gone target changed the list")
    }
}

/// Somewhere for the binding under test to write to.
private final class TargetBox {
    var targets: [GenericTarget]

    init(_ targets: [GenericTarget]) {
        self.targets = targets
    }
}

/// A preset is one tool at one place, so adding it twice watches the same folder
/// twice and shows two identical tiles — which is what the user saw.
@MainActor
final class PresetDuplicationTests: XCTestCase {
    private func section(_ targets: [GenericTarget]) -> GenericTargetsSection {
        GenericTargetsSection(targets: .constant(targets))
    }

    private var fixedPreset: GenericPreset {
        GenericPreset.all.first { $0.folderPrompt == nil }!
    }

    private var folderPreset: GenericPreset {
        GenericPreset.all.first { $0.folderPrompt != nil }!
    }

    func testAFixedPresetCanOnlyBeAddedOnce() {
        XCTAssertFalse(section([]).isExhausted(fixedPreset))
        XCTAssertTrue(section([fixedPreset.target()]).isExhausted(fixedPreset))
    }

    /// A per-project preset is a different target in every checkout, so it never
    /// runs out.
    func testAFolderPresetStaysAvailable() {
        let one = folderPreset.target(folder: URL(fileURLWithPath: "/tmp/a"))
        XCTAssertFalse(section([one]).isExhausted(folderPreset))
    }

    /// The folder picker is a sheet now, so the "user chose a folder" half of
    /// adding a per-project preset is its own step and can be tested without an
    /// open panel. It used to be spelled inline after a `runModal()`, which
    /// blocked the main run loop from inside the menu's tracking loop.
    func testAChosenFolderBecomesATargetExactlyOnce() {
        let box = TargetBox([])
        let section = GenericTargetsSection(
            targets: Binding(get: { box.targets }, set: { box.targets = $0 }))
        let folder = URL(fileURLWithPath: "/tmp/checkout-a")

        section.adopt(folderPreset, folder: folder)
        XCTAssertEqual(box.targets.map(\.watchedFolder), [folder])

        section.adopt(folderPreset, folder: folder)
        XCTAssertEqual(box.targets.count, 1, "the same folder was watched twice")

        section.adopt(folderPreset, folder: URL(fileURLWithPath: "/tmp/checkout-b"))
        XCTAssertEqual(box.targets.count, 2, "a second checkout is a second target")
    }

    /// A sheet needs a window. Without one the picker would have to fall back to
    /// a free-floating panel, which is the behaviour being replaced.
    func testTheSheetHasTheSettingsWindowToHangOff() throws {
        let suite = "com.perfectoweb.belay.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsWindow(
            settings: SettingsStore(defaults: defaults),
            state: AppState(),
            precise: PreciseDetection(),
            targets: { [] },
            statistics: { UsageStatistics() },
            onTargetsChanged: { _ in })

        settings.show(pane: .providers)
        XCTAssertIdentical(GenericTargetsSection.hostWindow, settings.window)
        settings.close()
    }

    func testAnotherPresetIsUnaffected() {
        let others = GenericPreset.all.filter { $0.id != fixedPreset.id && $0.folderPrompt == nil }
        for preset in others {
            XCTAssertFalse(section([fixedPreset.target()]).isExhausted(preset), preset.displayName)
        }
    }
}
