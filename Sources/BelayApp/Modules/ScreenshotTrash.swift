import BelaySupport
import Foundation

/// Moves one file to the Trash, by hand when macOS refuses the usual request.
///
/// A folder kept in iCloud Drive, which is where the Desktop lives on many
/// Macs, hands `trashItem` to the file provider daemon, and the daemon asks the
/// system whether Belay may touch the file in a way that must not raise a
/// question. The answer is "no permission" even after the user allowed the
/// Desktop, so every pass failed and nothing said why (found 2026-09-30).
/// Moving the file into the home Trash needs no such check. What is lost is
/// Put Back, which only Finder's own move records.
enum ScreenshotTrash {
    static var homeTrash: URL {
        UserHome.real.appending(path: ".Trash", directoryHint: .isDirectory)
    }

    static func move(_ url: URL) throws {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch CocoaError.fileWriteNoPermission {
            try moveByHand(url, to: homeTrash)
        }
    }

    /// A rename and nothing else: a Trash on another volume would mean a copy
    /// followed by a delete, and half of that is a file in two places.
    static func moveByHand(_ url: URL, to trash: URL, now: Date = Date()) throws {
        guard let here = volume(of: url), let there = volume(of: trash.deletingLastPathComponent()),
            here.isEqual(there)
        else { throw CocoaError(.fileWriteNoPermission) }
        do {
            try FileManager.default.moveItem(at: url, to: trash.appending(path: url.lastPathComponent))
        } catch CocoaError.fileWriteFileExists {
            // Never over a file already there: the second one takes the time,
            // the way Finder names it.
            try FileManager.default.moveItem(at: url, to: trash.appending(path: renamed(url, at: now)))
        }
    }

    static func renamed(_ url: URL, at now: Date) -> String {
        let time = Calendar.current.dateComponents([.hour, .minute, .second], from: now)
        let stamp = String(
            format: "%02d.%02d.%02d", time.hour ?? 0, time.minute ?? 0, time.second ?? 0)
        let stem = url.deletingPathExtension().lastPathComponent
        return url.pathExtension.isEmpty ? "\(stem) \(stamp)" : "\(stem) \(stamp).\(url.pathExtension)"
    }

    private static func volume(of url: URL) -> NSObjectProtocol? {
        (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier
    }
}
