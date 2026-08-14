import Foundation
import Testing

@testable import BelaySupport

/// The grants behind the folders a user picks for a generic target.
///
/// The bug this covers was not that a bookmark expired. It was that nobody ever
/// took one: the sandboxed build handed the generic provider the grant for
/// `~/.claude`, every picked folder was outside it, and the open panel's scope
/// died with the process. So the tests worth having are about *which* grant
/// answers for a URL, and about a folder still being readable on the launch
/// after the one it was picked in.
@Suite final class FolderGrantsTests: Sendable {
    private let bookmarks = FakeBookmarks()
    private let store = MemoryBookmarkStore()
    private let base: URL
    private let work: URL
    private let notes: URL

    init() throws {
        base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("belay-folders-\(UUID().uuidString)", isDirectory: true)
        work = base.appendingPathComponent("work", isDirectory: true)
        notes = base.appendingPathComponent("notes", isDirectory: true)
        for folder in [work, notes] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("{}\n".utf8).write(to: folder.appendingPathComponent("file.json"))
        }
    }

    deinit { try? FileManager.default.removeItem(at: base) }

    private func grants() -> FolderGrants {
        FolderGrants(store: store, bookmarks: bookmarks)
    }

    // MARK: - The launch after

    @Test func aPickedFolderIsStillReadableOnTheNextLaunch() throws {
        let first = grants()
        try first.remember(work)
        #expect(first.remembered.map(\.lastPathComponent) == ["work"])
        first.relinquish()

        // A second instance built from the same store is what the next launch
        // gets. It has never seen an open panel.
        let second = grants()
        #expect(second.remembered.map(\.lastPathComponent) == ["work"])
        #expect(second.hasAccess(to: work.appendingPathComponent("file.json")))
        second.relinquish()
    }

    @Test func aFolderThatWasNeverPickedIsNotClaimed() throws {
        let held = grants()
        try held.remember(work)
        // `notes` was never granted, so nothing here should pretend to own it.
        #expect(held.remembered.contains(notes) == false)
        held.relinquish()
    }

    // MARK: - Several folders at once

    @Test func eachFolderIsReadThroughItsOwnGrant() throws {
        let held = grants()
        try held.remember(work)
        try held.remember(notes)
        #expect(held.remembered.count == 2)

        // Two grants, two keys: one bookmark overwriting the other would leave
        // whichever was picked first unreadable.
        #expect(store.data(forKey: FolderGrants.key(for: work)) != nil)
        #expect(store.data(forKey: FolderGrants.key(for: notes)) != nil)
        #expect(FolderGrants.key(for: work) != FolderGrants.key(for: notes))
        held.relinquish()
    }

    @Test func aFolderInsideAnotherKeepsItsOwnGrant() throws {
        let inner = work.appendingPathComponent("inner", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        let file = inner.appendingPathComponent("file.json")
        try Data("{}\n".utf8).write(to: file)

        let held = grants()
        try held.remember(work)
        try held.remember(inner)
        #expect(held.hasAccess(to: file))

        // Dropping the outer folder must not take the inner one with it. If the
        // inner file were being read through its parent's grant, this is where
        // it would stop working.
        held.forget(work)
        #expect(held.remembered.map(\.lastPathComponent) == ["inner"])
        #expect(held.hasAccess(to: file))
        held.relinquish()
    }

    // MARK: - Forgetting

    @Test func removingATargetTakesItsGrantWithIt() throws {
        let held = grants()
        try held.remember(work)
        try held.remember(notes)

        held.forget(work)
        #expect(held.remembered.map(\.lastPathComponent) == ["notes"])
        #expect(store.data(forKey: FolderGrants.key(for: work)) == nil)
        held.relinquish()

        // And it stays forgotten across a launch.
        let next = grants()
        #expect(next.remembered.map(\.lastPathComponent) == ["notes"])
        next.relinquish()
    }

    // MARK: - Scope balance

    @Test func everyScopeThisOpensIsClosed() throws {
        let held = grants()
        try held.remember(work)
        try held.remember(notes)
        _ = held.hasAccess(to: work.appendingPathComponent("file.json"))
        try held.withAccess(to: notes.appendingPathComponent("file.json")) { _ in }
        held.relinquish()
        #expect(bookmarks.tally.outstanding == 0)
    }
}
