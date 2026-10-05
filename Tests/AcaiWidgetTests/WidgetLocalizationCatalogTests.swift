import Foundation
import Testing

/// The widget ships in English, German and French, and only Xcode compiles an `.xcstrings`, so a
/// missing identifier or translation is invisible under `swift build` and reaches users as raw
/// text. Mirrors what `AcaiAppTests`' `LocalizationCatalogTests` does for the app, over the
/// widget's two catalogs: the module's own chrome, and the extension target's App Intents strings
/// (which must live there, since App Intents metadata resolves them from the main bundle).
@Suite("Widget localization catalogs", .timeLimit(.minutes(1)))
struct WidgetLocalizationCatalogTests {
    private static let shippedLanguages: Set<String> = ["en", "de", "fr"]

    private let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private var moduleSources: URL { repositoryRoot.appendingPathComponent("Sources/AcaiWidget") }

    private var chromeCatalog: URL {
        moduleSources.appendingPathComponent("Resources/Localizable.xcstrings")
    }

    private var intentCatalog: URL {
        repositoryRoot.appendingPathComponent("App/Widget/AppIntents.xcstrings")
    }

    @Test("Every identifier the views use exists in the widget's own catalog, exactly once")
    func everyChromeIdentifierExists() throws {
        let keys = Set(try catalogStrings(at: chromeCatalog).keys)
        for identifier in try identifiers(matching: #"\.widget\("([^"]+)"\)"#) {
            #expect(keys.contains(identifier), "'\(identifier)' is missing from the widget catalog")
        }
    }

    @Test("Every identifier the intents use exists in the extension's App Intents catalog")
    func everyIntentIdentifierExists() throws {
        let keys = Set(try catalogStrings(at: intentCatalog).keys)
        let pattern = #"LocalizedStringResource\("([^"]+)", table: "AppIntents"\)"#
        for identifier in try identifiers(matching: pattern) {
            #expect(keys.contains(identifier), "'\(identifier)' is missing from the App Intents catalog")
        }
    }

    @Test("No catalog entry is unused, so a reworded view can't leave a stale identifier behind")
    func noCatalogEntryIsUnused() throws {
        let used = try identifiers(matching: #"\.widget\("([^"]+)"\)"#)
        for key in try catalogStrings(at: chromeCatalog).keys {
            #expect(used.contains(key), "'\(key)' is in the catalog but no view uses it")
        }
        let usedIntents = try identifiers(matching: #"LocalizedStringResource\("([^"]+)", table: "AppIntents"\)"#)
        for key in try catalogStrings(at: intentCatalog).keys {
            #expect(usedIntents.contains(key), "'\(key)' is in the App Intents catalog but nothing uses it")
        }
    }

    @Test("Every entry in both catalogs carries all three shipped languages")
    func everyEntryIsTranslated() throws {
        for catalog in [chromeCatalog, intentCatalog] {
            let name = catalog.lastPathComponent
            for (key, entry) in try catalogStrings(at: catalog) {
                let localizations = entry["localizations"] as? [String: Any] ?? [:]
                let missing = Self.shippedLanguages.subtracting(localizations.keys)
                #expect(missing.isEmpty, "\(name): '\(key)' is missing \(missing.sorted())")
            }
        }
    }

    @Test("Every plural form and substitution is filled in, in every language")
    func everyPluralFormIsTranslated() throws {
        for (key, entry) in try catalogStrings(at: chromeCatalog) {
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            for language in Self.shippedLanguages.sorted() {
                guard let localization = localizations[language] as? [String: Any] else { continue }
                for (label, value) in resolvedValues(in: localization) {
                    #expect(!value.isEmpty, "'\(key)' (\(language)) has an empty \(label)")
                }
            }
        }
    }

    @Test("A key with a placeholder spells it %lld, matching how the views interpolate a count")
    func placeholdersAreIntegerFormatted() throws {
        for key in try catalogStrings(at: chromeCatalog).keys where key.contains("%") {
            let specifiers = key.components(separatedBy: "%").dropFirst()
            for specifier in specifiers {
                #expect(specifier.hasPrefix("lld"), "'\(key)' uses a placeholder other than %lld")
            }
        }
    }

    /// Every `stringUnit` value reachable in one language: the flat one, each plural form, and each
    /// substitution's plural forms.
    private func resolvedValues(in localization: [String: Any]) -> [(String, String)] {
        var values: [(String, String)] = []
        if let unit = localization["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
            values.append(("value", value))
        }
        values += pluralValues(in: localization["variations"] as? [String: Any], label: "plural form")
        for (name, substitution) in localization["substitutions"] as? [String: Any] ?? [:] {
            let variations = (substitution as? [String: Any])?["variations"] as? [String: Any]
            values += pluralValues(in: variations, label: "substitution '\(name)'")
        }
        return values
    }

    private func pluralValues(in variations: [String: Any]?, label: String) -> [(String, String)] {
        guard let plural = variations?["plural"] as? [String: Any] else { return [] }
        return plural.compactMap { form, body in
            guard let unit = (body as? [String: Any])?["stringUnit"] as? [String: Any],
                  let value = unit["value"] as? String
            else { return nil }
            return ("\(label) '\(form)'", value)
        }
    }

    private func catalogStrings(at url: URL) throws -> [String: [String: Any]] {
        let object = try JSONSerialization.jsonObject(with: try Data(contentsOf: url))
        let catalog = try #require(object as? [String: Any])
        return try #require(catalog["strings"] as? [String: [String: Any]])
    }

    /// Identifiers at every call site, with an interpolation rewritten to the `%lld` the catalog
    /// key carries — `.widget("View.Foo.Types \(count)")` looks up `View.Foo.Types %lld`.
    private func identifiers(matching pattern: String) throws -> Set<String> {
        let regex = try NSRegularExpression(pattern: pattern)
        let interpolation = try NSRegularExpression(pattern: #"\\\([^)]+\)"#)
        var found: Set<String> = []
        for url in try swiftFiles() {
            let source = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            for match in regex.matches(in: source, range: range) {
                guard let captured = Range(match.range(at: 1), in: source) else { continue }
                let raw = String(source[captured])
                found.insert(interpolation.stringByReplacingMatches(
                    in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "%lld"))
            }
        }
        return found
    }

    private func swiftFiles() throws -> [URL] {
        let enumerator = FileManager.default.enumerator(at: moduleSources, includingPropertiesForKeys: nil)
        let all = try #require(enumerator)
        return all.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
