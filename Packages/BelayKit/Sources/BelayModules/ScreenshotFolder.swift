import Foundation
import UniformTypeIdentifiers

/// Reads a folder and answers with the screen captures in it.
///
/// A capture is recognised by the mark macOS itself leaves on the file, never
/// by its name. The name is localised ("Screenshot", "Снимок экрана"), can be
/// changed in the capture settings, and is the first thing a person edits; the
/// mark survives all three and is absent from every file that is not a capture,
/// which is the property that makes moving things to the Trash defensible.
public enum ScreenshotFolder {
    static let captureMark = "com.apple.metadata:kMDItemIsScreenCapture"
    static let tagsMark = "com.apple.metadata:_kMDItemUserTags"

    private static let keys: [URLResourceKey] = [
        .isRegularFileKey, .creationDateKey, .contentModificationDateKey, .contentTypeKey
    ]

    /// The folder's own files only. A capture someone filed into a subfolder
    /// has been put somewhere on purpose.
    public static func candidates(in folder: URL) throws -> [ScreenshotCandidate] {
        let files = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants])
        return files.compactMap(candidate(at:))
    }

    static func candidate(at url: URL) -> ScreenshotCandidate? {
        guard let values = try? url.resourceValues(forKeys: Set(keys)),
            values.isRegularFile == true,
            let created = values.creationDate,
            isCapture(url)
        else { return nil }
        return ScreenshotCandidate(
            url: url,
            created: created,
            modified: values.contentModificationDate ?? created,
            isRecording: values.contentType?.conforms(to: .movie) ?? false,
            isTagged: isTagged(url)
        )
    }

    static func isCapture(_ url: URL) -> Bool {
        guard let value = propertyList(named: captureMark, of: url) else { return false }
        return (value as? Bool) ?? ((value as? NSNumber)?.boolValue ?? false)
    }

    static func isTagged(_ url: URL) -> Bool {
        guard let tags = propertyList(named: tagsMark, of: url) as? [Any] else { return false }
        return !tags.isEmpty
    }

    /// Spotlight's attributes are binary property lists stored as extended
    /// attributes, which is why this reads the file and not the index: the
    /// index can be off, stale or absent on an external disk, the file cannot.
    private static func propertyList(named name: String, of url: URL) -> Any? {
        let path = url.path
        let length = getxattr(path, name, nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: length)
        let read = getxattr(path, name, &bytes, length, 0, 0)
        guard read > 0 else { return nil }
        return try? PropertyListSerialization.propertyList(
            from: Data(bytes.prefix(read)), options: [], format: nil)
    }
}
