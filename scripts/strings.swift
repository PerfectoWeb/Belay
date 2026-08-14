// Round-trips every user-visible string between the catalogue and one CSV per
// language, so text can be rewritten in a spreadsheet instead of in JSON.
//
//   swift scripts/strings.swift export            # catalogue -> Localization/*.csv
//   swift scripts/strings.swift import            # Localization/*.csv -> catalogue
//   swift scripts/strings.swift import --dry-run  # report what would change
//
// Rewriting English does not rename anything. A key in this catalogue started
// life as its English text, but the two are separate fields, so a reword lands
// in the `en` value and the key stays as it is. That is what a .strings file has
// always done, it keeps the Swift sources out of it, and it is the only version
// of this that survives the sources wrapping long strings across lines with
// backslash continuations. See Localization/README.md.
import Foundation

let catalogue = URL(fileURLWithPath: "Resources/Localizable.xcstrings")
let folder = URL(fileURLWithPath: "Localization")
let sourceRoots = ["Sources", "Packages/BelayKit/Sources"]

// MARK: - Catalogue

struct Catalogue {
    var root: [String: Any]
    var strings: [String: Any]

    init() throws {
        let data = try Data(contentsOf: catalogue)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let strings = root["strings"] as? [String: Any]
        else { throw Failure("Resources/Localizable.xcstrings is not the shape we expect") }
        self.root = root
        self.strings = strings
    }

    var languages: [String] {
        Set(
            strings.values.compactMap { ($0 as? [String: Any])?["localizations"] as? [String: Any] }
                .flatMap(\.keys)
        ).sorted()
    }

    func value(_ key: String, _ language: String) -> String? {
        guard let entry = strings[key] as? [String: Any],
            let localizations = entry["localizations"] as? [String: Any],
            let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
        else { return nil }
        return unit["value"] as? String
    }

    func state(_ key: String, _ language: String) -> String {
        guard let entry = strings[key] as? [String: Any],
            let localizations = entry["localizations"] as? [String: Any],
            let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
        else { return "" }
        return unit["state"] as? String ?? ""
    }

    /// A value that changed has by definition been looked at, so it is marked
    /// reviewed; one that did not keeps whatever state it had, which is how
    /// `needs_review` survives an import that only touched other rows.
    mutating func set(_ value: String, key: String, language: String) {
        var entry = strings[key] as? [String: Any] ?? ["extractionState": "manual"]
        var localizations = entry["localizations"] as? [String: Any] ?? [:]
        let existing = self.state(key, language)
        let keep = value == self.value(key, language) && !existing.isEmpty
        localizations[language] = [
            "stringUnit": ["state": keep ? existing : "translated", "value": value]
        ]
        entry["localizations"] = localizations
        strings[key] = entry
    }

    mutating func rename(_ old: String, to new: String) {
        guard old != new, let entry = strings[old] else { return }
        strings[new] = entry
        strings[old] = nil
    }

    /// Writes the catalogue back in one shape, on every machine.
    ///
    /// Neither half of this is cosmetic. `JSONSerialization` has changed both
    /// its spacing and its `.sortedKeys` order between OS releases: the
    /// committed catalogue is written `"key": "value"` with its top level in
    /// plain code-point order, and a current Foundation writes `"key" : "value"`
    /// and puts `"%@ · %@"` first. Re-saving the file *without changing a word*
    /// therefore rewrote fourteen thousand of its lines, which turns every
    /// localisation change into a diff nobody can read and buries the one line
    /// that actually changed.
    ///
    /// So the top level is emitted here rather than handed to Foundation, and
    /// each entry is pretty-printed on its own. Entry keys are all ASCII, where
    /// the two orderings agree, so only the outer loop needs to be ours.
    func save() throws {
        var out = "{\n"
        var root = root
        root["strings"] = strings
        let keys = root.keys.sorted()
        for (index, key) in keys.enumerated() {
            let comma = index == keys.count - 1 ? "" : ","
            if key == "strings" {
                out += "  \(Self.scalar(key)): {\n"
                let inner = strings.keys.sorted()
                for (position, name) in inner.enumerated() {
                    let body = Self.indent(try Self.pretty(strings[name]!), by: 4)
                    out += "    \(Self.scalar(name)): \(body)"
                    out += position == inner.count - 1 ? "\n" : ",\n"
                }
                out += "  }\(comma)\n"
            } else {
                out += "  \(Self.scalar(key)): \(try Self.pretty(root[key]!))\(comma)\n"
            }
        }
        out += "}\n"
        try out.write(to: catalogue, atomically: true, encoding: .utf8)
    }

    /// One value, pretty-printed the way the rest of the file is.
    static func pretty(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: value,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
        let text = String(data: data, encoding: .utf8)!
        // Anchored on the start of a line, which is what makes it safe: after
        // pretty-printing a key is always first on its own line, so a `" : "`
        // inside a translation is never touched.
        let spaced = try NSRegularExpression(
            pattern: #"^(\s*"(?:[^"\\]|\\.)*") : "#, options: [.anchorsMatchLines])
        return spaced.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1: ")
    }

    /// A bare string, encoded as JSON.
    static func scalar(_ value: String) -> String {
        let data = try! JSONSerialization.data(
            withJSONObject: value, options: [.withoutEscapingSlashes, .fragmentsAllowed])
        return String(data: data, encoding: .utf8)!
    }

    /// Every line but the first gets the indent, because the first is already
    /// sitting after its key.
    static func indent(_ text: String, by spaces: Int) -> String {
        let pad = String(repeating: " ", count: spaces)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { $0.offset == 0 ? String($0.element) : pad + $0.element }
            .joined(separator: "\n")
    }

}

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: - Where a string appears

/// Maps each key to the screen it shows up on, by looking for the literal in the
/// sources. Translators asked for the same thing every translator asks for: not
/// the string, but where it lands and what sits next to it.
func screens() throws -> (String) -> String {
    var contents: [URL: String] = [:]
    for root in sourceRoots {
        let base = URL(fileURLWithPath: root)
        guard let walk = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
        else { continue }
        for case let url as URL in walk where url.pathExtension == "swift" {
            // Long copy is wrapped with line continuations inside `"""` blocks,
            // so the literal only matches once the wrapping is undone.
            contents[url] = (try? String(contentsOf: url, encoding: .utf8))?
                .replacingOccurrences(of: "\\\\\n[ \t]*", with: "", options: .regularExpression)
        }
    }
    let label: (URL) -> String = { url in
        let path = url.path
        if path.contains("/Panel/") { return "Panel" }
        if path.contains("/Onboarding/") { return "Welcome" }
        if path.contains("/Statistics/") { return "Statistics" }
        if path.contains("AboutPane") || path.contains("AboutLink") { return "Settings: About" }
        if path.contains("GeneralSettings") || path.contains("AppLanguage")
            || path.contains("LoginItem") || path.contains("ReleaseChecker")
        { return "Settings: General" }
        if path.contains("BehaviourSettings") { return "Settings: Behaviour" }
        if path.contains("NotificationSettings") || path.contains("Notifier") {
            return "Settings: Notifications"
        }
        if path.contains("Providers") || path.contains("GenericTarget")
            || path.contains("HookPreview") || path.contains("PreciseDetection")
        { return "Settings: Providers" }
        if path.contains("Settings") { return "Settings" }
        if path.contains("StatusItem") { return "Menu bar" }
        if path.contains("/Packages/") { return "Detection" }
        return "App"
    }
    return { key in
        // A key with a specifier in it is written in the source as an
        // interpolation, so `%lld agents` has to match `\(count) agents`.
        // Two levels of nesting covers what the sources actually contain, down
        // to `\(Int((charge * 100).rounded()))`.
        var inner = "[^()]*"
        for _ in 0..<2 { inner = "(?:[^()]|\\(\(inner)\\))*" }
        let interpolation = "\\\\\\(\(inner)\\)"
        var pattern = NSRegularExpression.escapedPattern(for: key)
        for specifier in ["%lld", "%ld", "%@", "%d"] {
            pattern = pattern.replacingOccurrences(
                of: specifier, with: "(?:\\Q\(specifier)\\E|\(interpolation))")
        }
        // A literal percent is doubled in a format string and single in source.
        pattern = pattern.replacingOccurrences(of: "%%", with: "%")
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
        let found = contents.filter { _, text in
            regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }.keys.map(label)
        // Worth saying out loud rather than leaving blank: a string no source
        // file asks for is one nobody should spend time rewriting.
        return found.isEmpty ? "(unused)" : Set(found).sorted().joined(separator: ", ")
    }
}

/// Every format specifier, in order. A translation that drops one or reorders
/// them crashes at the call site rather than looking wrong, so this is checked
/// on the way back in and not left to review.
func placeholders(_ text: String) -> [String] {
    let pattern = try! NSRegularExpression(pattern: "%(?:\\d+\\$)?(?:@|lld|ld|d|f|\\.\\d+f|%)")
    let range = NSRange(text.startIndex..., in: text)
    return pattern.matches(in: text, range: range).compactMap {
        Range($0.range, in: text).map { String(text[$0]) }
    }.filter { $0 != "%%" }
}

// MARK: - CSV

func csvField(_ value: String) -> String {
    guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return value }
    return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

func csvRows(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var quoted = false
    var index = text.startIndex
    while index < text.endIndex {
        let character = text[index]
        if quoted {
            if character == "\"" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = next
                } else {
                    quoted = false
                }
            } else {
                field.append(character)
            }
        } else {
            switch character {
            case "\"": quoted = true
            case ",":
                row.append(field)
                field = ""
            case "\n":
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            case "\r": break
            default: field.append(character)
            }
        }
        index = text.index(after: index)
    }
    if !field.isEmpty || !row.isEmpty {
        row.append(field)
        rows.append(row)
    }
    return rows
}

let columns = ["key", "screen", "status", "placeholders", "source", "translation"]

// MARK: - Export

func export() throws {
    let catalogue = try Catalogue()
    let screen = try screens()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let keys = catalogue.strings.keys.sorted()
    var located: [String: String] = [:]
    for key in keys { located[key] = screen(key) }

    for language in catalogue.languages {
        // English is the source, so its editable column starts as a copy of
        // itself: changing it is how a reword is requested.
        var out = columns.map(csvField).joined(separator: ",") + "\n"
        for key in keys {
            let source = catalogue.value(key, "en") ?? key
            let translation = catalogue.value(key, language) ?? ""
            out +=
                [
                    key, located[key] ?? "", catalogue.state(key, language),
                    placeholders(source).joined(separator: " "), source, translation,
                ].map(csvField).joined(separator: ",") + "\n"
        }
        let url = folder.appendingPathComponent("\(language).csv")
        try ("\u{FEFF}" + out).write(to: url, atomically: true, encoding: .utf8)
        print("wrote \(url.path) — \(keys.count) strings")
    }
}

// MARK: - Import

func runImport(dryRun: Bool, prune: Bool) throws {
    var catalogue = try Catalogue()
    var problems: [String] = []
    var unknown: [String] = []
    var updates = 0
    var kept: Set<String> = []

    for language in ["en"] + catalogue.languages.filter({ $0 != "en" }) {
        let url = folder.appendingPathComponent("\(language).csv")
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
        let rows = csvRows(raw.replacingOccurrences(of: "\u{FEFF}", with: ""))
        guard let header = rows.first, header == columns else {
            problems.append("\(language).csv: header must be \(columns.joined(separator: ","))")
            continue
        }
        for (offset, row) in rows.dropFirst().enumerated() where row.count == columns.count {
            let line = offset + 2
            let key = row[0]
            let source = row[4]
            let translation = row[5].trimmingCharacters(in: .whitespacesAndNewlines)

            // A file reviewed elsewhere goes stale the moment a string is
            // retired here. Reported, not written: setting it would quietly put
            // the retired string back.
            guard catalogue.strings[key] != nil else {
                if language == "en" { unknown.append(key) }
                continue
            }
            guard !translation.isEmpty else {
                problems.append("\(language).csv:\(line): empty translation for \"\(key)\"")
                continue
            }
            // House rule, and one a spreadsheet breaks by itself: some editors
            // turn a typed hyphen into an em dash without being asked.
            if translation.contains("—") || translation.contains("–") {
                problems.append("\(language).csv:\(line): contains a dash we do not use")
            }
            if placeholders(translation) != placeholders(source) {
                problems.append(
                    "\(language).csv:\(line): placeholders are \(placeholders(translation)), "
                        + "source has \(placeholders(source))")
                continue
            }
            if catalogue.value(key, language) != translation { updates += 1 }
            catalogue.set(translation, key: key, language: language)
            if language == "en" { kept.insert(key) }
        }
    }

    // Off unless asked for. A file being reviewed elsewhere goes stale the
    // moment a string is added here, and importing it must not then delete the
    // additions just because an older copy has never heard of them.
    let dropped = prune ? catalogue.strings.keys.filter { !kept.contains($0) } : []
    dropped.forEach { catalogue.strings[$0] = nil }

    guard problems.isEmpty else {
        problems.forEach { print("error: \($0)") }
        throw Failure("\(problems.count) problems; nothing was written")
    }
    print("\(updates) strings changed, \(dropped.count) removed, \(unknown.count) unknown")
    dropped.forEach { print("removed \"\($0)\"") }
    unknown.forEach { print("ignored, no longer in the catalogue: \"\($0)\"") }
    guard !dryRun else { return }
    try catalogue.save()
}

// MARK: - Check

/// Compares the keys the compiler saw against the catalogue.
///
/// This is the check that would have caught what shipped: a string the code asks
/// for but the catalogue has never heard of falls back to English in every
/// language, silently, and only somebody running the app in Russian finds out.
func check(configuration: String) throws {
    let catalogue = try Catalogue()
    var problems: [String] = []

    // Scoped to one configuration: a Release build left in DerivedData from
    // some earlier day reports the keys that existed on that day.
    let build = URL(fileURLWithPath: "build/DerivedData/Build/Intermediates.noindex")
        .appendingPathComponent("Belay.build/\(configuration)")
    guard let walk = FileManager.default.enumerator(at: build, includingPropertiesForKeys: nil)
    else { throw Failure("no \(configuration) build products; build the app target first") }

    var used: Set<String> = []
    for case let url as URL in walk where url.pathExtension == "stringsdata" {
        guard let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tables = root["tables"] as? [String: Any]
        else { continue }
        for case let entries as [[String: Any]] in tables.values {
            used.formUnion(entries.compactMap { $0["key"] as? String })
        }
    }
    guard !used.isEmpty else { throw Failure("no strings were extracted; is the build stale?") }
    for key in used.subtracting(catalogue.strings.keys).sorted() {
        problems.append("not in the catalogue: \"\(key)\"")
    }

    // The package targets are not extracted at all, which is why their strings
    // went untranslated for so long without anything noticing. Read them out of
    // the source instead, and match with the specifiers as wildcards so an
    // interpolation lines up with the `%@` the catalogue stores.
    let keys = catalogue.strings.keys.map { key -> NSRegularExpression? in
        var pattern = NSRegularExpression.escapedPattern(for: key)
        for specifier in ["%lld", "%ld", "%@", "%d"] {
            pattern = pattern.replacingOccurrences(of: specifier, with: ".+")
        }
        return try? NSRegularExpression(pattern: "^\(pattern)$", options: .dotMatchesLineSeparators)
    }
    for (file, literal) in try packageLiterals() {
        let wildcarded = literal.replacingOccurrences(
            of: "\\\\\\([^)]*\\)", with: "x", options: .regularExpression)
        let range = NSRange(wildcarded.startIndex..., in: wildcarded)
        let matched = keys.contains { $0?.firstMatch(in: wildcarded, range: range) != nil }
        if !matched { problems.append("\(file): not in the catalogue: \"\(literal)\"") }
    }

    problems.forEach { print("error: \($0)") }
    guard problems.isEmpty else {
        throw Failure("\(problems.count) strings would fall back to English everywhere")
    }
    print("\(used.count) app strings and every package string are in the catalogue")
}

/// Every literal passed to `String(localized:)` under `Packages`, with the line
/// wrapping undone.
func packageLiterals() throws -> [(String, String)] {
    let pattern = try NSRegularExpression(
        pattern: "localized:\\s*(?:\"\"\"(.*?)\"\"\"|\"((?:[^\"\\\\]|\\\\.)*)\")",
        options: .dotMatchesLineSeparators)
    var found: [(String, String)] = []
    let base = URL(fileURLWithPath: "Packages/BelayKit/Sources")
    guard let walk = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
    else { return [] }
    for case let url as URL in walk where url.pathExtension == "swift" {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
        let text = raw.replacingOccurrences(
            of: "\\\\\n[ \t]*", with: "", options: .regularExpression)
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let group = match.range(at: 1).location == NSNotFound ? 2 : 1
            guard let range = Range(match.range(at: group), in: text) else { continue }
            found.append(
                (
                    url.lastPathComponent,
                    String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                ))
        }
    }
    return found
}

// MARK: - Entry

do {
    switch CommandLine.arguments.dropFirst().first {
    case "export": try export()
    case "import":
        try runImport(
            dryRun: CommandLine.arguments.contains("--dry-run"),
            prune: CommandLine.arguments.contains("--prune"))
    case "check":
        try check(configuration: CommandLine.arguments.dropFirst(2).first ?? "Debug")
    default: print("usage: swift scripts/strings.swift export|import|check [--dry-run] [--prune]")
    }
} catch {
    print("error: \(error)")
    exit(1)
}
