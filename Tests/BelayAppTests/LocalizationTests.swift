import Foundation
import XCTest

@testable import Belay

/// The string catalogue.
///
/// Two failure modes matter and neither shows up in English. A language that
/// silently stops shipping falls back to English and looks like nothing is
/// wrong; a translation whose format specifiers do not match the source reads
/// the wrong argument off the stack, which is a crash or garbage on a machine
/// nobody testing the app is using.
final class LocalizationTests: XCTestCase {
    private var languages: [String] {
        AppLanguage.offered.filter { $0 != .system }.map(\.rawValue)
    }

    func testEveryOfferedLanguageIsActuallyInTheBundle() {
        let shipped = Set(Bundle.main.localizations)
        for code in languages {
            XCTAssertTrue(
                shipped.contains(code),
                "the picker offers \(code) but the bundle has no \(code).lproj — it would silently show English"
            )
        }
    }

    func testEnglishIsTheFallback() {
        XCTAssertTrue(Bundle.main.localizations.contains("en"))
        XCTAssertEqual(Bundle.main.developmentLocalization, "en")
    }

    /// Reads the compiled tables rather than the source catalogue, so this fails
    /// if a translation is dropped anywhere between the file and the app.
    private func table(_ code: String) throws -> [String: String] {
        let bundle = try XCTUnwrap(
            Bundle.main.path(forResource: code, ofType: "lproj").map(Bundle.init(path:)) ?? nil,
            "no \(code).lproj")
        let url = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "strings"))
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: String])
    }

    func testNoLanguageIsMostlyEmpty() throws {
        let english = try table("en")
        XCTAssertGreaterThan(english.count, 100, "the catalogue did not compile into the bundle")
        for code in languages where code != "en" {
            let translated = try table(code)
            XCTAssertEqual(
                translated.count, english.count,
                "\(code) is missing \(english.count - translated.count) strings")
            XCTAssertTrue(
                translated.values.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                "\(code) has an empty translation")
        }
    }

    /// `%@` where the source has `%lld` reads a pointer as an integer. This is
    /// the test that earns the whole file.
    func testFormatSpecifiersSurviveTranslation() throws {
        let english = try table("en")
        for code in languages where code != "en" {
            let translated = try table(code)
            for (key, source) in english {
                guard let value = translated[key] else { continue }
                XCTAssertEqual(
                    Self.specifiers(in: source), Self.specifiers(in: value),
                    "\(code): \"\(key)\" has \(Self.specifiers(in: value)) but the source has \(Self.specifiers(in: source))"
                )
            }
        }
    }

    /// A translation that is identical to English everywhere means the file was
    /// generated but never filled in.
    func testTranslationsAreNotJustCopiesOfEnglish() throws {
        let english = try table("en")
        for code in languages where code != "en" {
            let translated = try table(code)
            let differing = translated.filter { key, value in english[key] != value }.count
            XCTAssertGreaterThan(
                Double(differing) / Double(max(english.count, 1)), 0.8,
                "\(code) matches English for \(english.count - differing) strings")
        }
    }

    /// The panel's headline block reserves two lines and truncates at the
    /// second, so a sentence that wraps is a sentence that can lose its ending
    /// in a language nobody testing the app reads. Every status sentence has to
    /// fit the detail column on one line, everywhere.
    func testEveryPanelStatusFitsOneLine() throws {
        let statuses: [PanelStatus] = [
            .off, .armed, .alwaysOn, .working, .awaitingUser, .coolingDown,
            .batteryLow(percent: 18), .maxDurationReached
        ]
        var measured = 0
        for code in languages {
            let table = try self.table(code)
            for status in statuses {
                let sentence = try XCTUnwrap(
                    table[status.detail.key], "\(code) has no \"\(status.detail.key)\"")
                let rendered = sentence
                    .replacingOccurrences(of: "%lld", with: "18")
                    .replacingOccurrences(of: "%%", with: "%")
                let width = (rendered as NSString).size(
                    withAttributes: [.font: PanelStatusLine.detailFont]
                ).width
                XCTAssertLessThanOrEqual(
                    width, PanelStatusLine.detailWidth,
                    "\(code): \"\(rendered)\" wraps in the panel")
                measured += 1
            }
        }
        XCTAssertEqual(measured, statuses.count * languages.count, "some sentences were skipped")
    }

    private static func specifiers(in text: String) -> [String] {
        let pattern = try? NSRegularExpression(pattern: "%(?:\\d+\\$)?(?:lld|ld|[@dfsu%])")
        let range = NSRange(text.startIndex..., in: text)
        let matches = pattern?.matches(in: text, range: range) ?? []
        return
            matches
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
            .filter { $0 != "%%" }
            .sorted()
    }
}
