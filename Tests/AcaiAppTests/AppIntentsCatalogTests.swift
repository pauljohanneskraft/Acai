import Foundation
import Testing

/// `LocalizationCatalogTests`, over the two catalogs that live in the app targets rather than in this
/// package. App Intents resolves an intent's static strings from the main bundle only, so they cannot
/// go through `.app(_:)` and `LocalizationCatalogTests` never sees them — a missing phrase or an
/// untranslated title would reach users as raw text, or as a phrase Siri only accepts in English.
@Suite("App Intents catalogs", .timeLimit(.minutes(1)))
struct AppIntentsCatalogTests {

    private static let shippedLanguages: Set<String> = ["en", "de", "fr"]

    private let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private var moduleSources: URL { repositoryRoot.appendingPathComponent("Sources/AcaiApp") }

    private var intentCatalog: URL { repositoryRoot.appendingPathComponent("App/Shared/AppIntents.xcstrings") }

    private var phraseCatalog: URL { repositoryRoot.appendingPathComponent("App/Shared/AppShortcuts.xcstrings") }

    @Test("Every identifier the intents use exists in the app's App Intents catalog")
    func everyIntentIdentifierExists() throws {
        let keys = Set(try catalogStrings(at: intentCatalog).keys)
        for identifier in try intentIdentifiers() {
            #expect(keys.contains(identifier), "'\(identifier)' is missing from the App Intents catalog")
        }
    }

    @Test("No App Intents entry is unused, so a reworded intent can't leave a stale identifier behind")
    func noIntentEntryIsUnused() throws {
        let used = try intentIdentifiers()
        for key in try catalogStrings(at: intentCatalog).keys {
            #expect(used.contains(key), "'\(key)' is in the App Intents catalog but no intent uses it")
        }
    }

    /// The system reads the phrase list out of the built metadata, where `\(.applicationName)` is
    /// `${applicationName}`, so a phrase is keyed by its own English text and a reworded phrase
    /// silently loses its translations unless the key moves with it.
    @Test("Every phrase the provider declares is a key in the shortcuts catalog, and none is stale")
    func everyPhraseIsInTheCatalog() throws {
        let keys = Set(try catalogStrings(at: phraseCatalog).keys)
        let declared = try phrases()
        #expect(!declared.isEmpty, "no phrases were found in the provider — has the spelling changed?")
        for phrase in declared {
            #expect(keys.contains(phrase), "the phrase '\(phrase)' is missing from the shortcuts catalog")
        }
        for key in keys {
            #expect(declared.contains(key), "'\(key)' is in the shortcuts catalog but no shortcut says it")
        }
    }

    @Test("Every phrase names the app, which the platform requires of all of them")
    func everyPhraseNamesTheApp() throws {
        for (key, entry) in try catalogStrings(at: phraseCatalog) {
            for (language, value) in values(in: entry) {
                #expect(
                    value.contains("${applicationName}"),
                    "'\(key)' (\(language)) has no ${applicationName}, so the platform rejects it")
            }
        }
    }

    @Test("Every entry in both catalogs carries all three shipped languages, filled in")
    func everyEntryIsTranslated() throws {
        for catalog in [intentCatalog, phraseCatalog] {
            let name = catalog.lastPathComponent
            for (key, entry) in try catalogStrings(at: catalog) {
                let localizations = entry["localizations"] as? [String: Any] ?? [:]
                let missing = Self.shippedLanguages.subtracting(localizations.keys)
                #expect(missing.isEmpty, "\(name): '\(key)' is missing \(missing.sorted())")
                for (language, value) in values(in: entry) {
                    #expect(!value.isEmpty, "\(name): '\(key)' (\(language)) is empty")
                }
            }
        }
    }

    @Test("A parameter a key names is one the intent interpolates into it")
    func placeholdersMatchTheIntents() throws {
        let catalog = try catalogStrings(at: intentCatalog)
        for (key, entry) in catalog where key.contains("$") {
            for (language, value) in values(in: entry) {
                let named = placeholders(in: key)
                #expect(
                    placeholders(in: value) == named,
                    "'\(key)' (\(language)) names \(placeholders(in: value).sorted()), not \(named.sorted())")
            }
        }
    }

    private func placeholders(in text: String) -> Set<String> {
        let regex = try? NSRegularExpression(pattern: #"\$\{([^}]+)\}"#)
        let range = NSRange(text.startIndex..., in: text)
        return Set((regex?.matches(in: text, range: range) ?? []).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        })
    }

    /// Every `"…", table: "AppIntents"` literal, whatever wraps it — `LocalizedStringResource`, a
    /// `Summary` or an `IntentDialog`, on one line or over two.
    private func intentIdentifiers() throws -> Set<String> {
        try identifiers(matching: #""([^"]+)", table: "AppIntents""#)
    }

    /// Each phrase an `AppShortcut` declares, as the metadata spells it.
    private func phrases() throws -> Set<String> {
        let source = try String(
            contentsOf: moduleSources.appendingPathComponent("Intents/AcaiShortcuts.swift"), encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #""([^"\n]*\\\(\.applicationName\)[^"\n]*)""#)
        let range = NSRange(source.startIndex..., in: source)
        let found = regex.matches(in: source, range: range).compactMap { match in
            Range(match.range(at: 1), in: source).map { String(source[$0]) }
        }
        return Set(found.map {
            $0.replacingOccurrences(of: #"\(.applicationName)"#, with: "${applicationName}")
        })
    }

    /// Every language's flat value. These catalogs hold no plurals or substitutions.
    private func values(in entry: [String: Any]) -> [(String, String)] {
        let localizations = entry["localizations"] as? [String: Any] ?? [:]
        return localizations.compactMap { language, localization in
            guard let unit = (localization as? [String: Any])?["stringUnit"] as? [String: Any],
                  let value = unit["value"] as? String
            else { return nil }
            return (language, value)
        }
    }

    private func catalogStrings(at url: URL) throws -> [String: [String: Any]] {
        let object = try JSONSerialization.jsonObject(with: try Data(contentsOf: url))
        let catalog = try #require(object as? [String: Any])
        return try #require(catalog["strings"] as? [String: [String: Any]])
    }

    private func identifiers(matching pattern: String) throws -> Set<String> {
        let regex = try NSRegularExpression(pattern: pattern)
        // A parameter the Shortcut picks is named in the key; any other interpolation is a count.
        let parameter = try NSRegularExpression(pattern: #"\\\(\\\.\$([A-Za-z0-9_]+)\)"#)
        let interpolation = try NSRegularExpression(pattern: #"\\\([^)]+\)"#)
        var found: Set<String> = []
        for url in try swiftFiles() {
            let source = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            for match in regex.matches(in: source, range: range) {
                guard let captured = Range(match.range(at: 1), in: source) else { continue }
                let raw = String(source[captured])
                let named = parameter.stringByReplacingMatches(
                    in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "\\${$1}")
                found.insert(interpolation.stringByReplacingMatches(
                    in: named, range: NSRange(named.startIndex..., in: named), withTemplate: "%lld"))
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
