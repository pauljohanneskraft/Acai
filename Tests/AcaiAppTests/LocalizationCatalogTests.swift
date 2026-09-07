import Foundation
import Testing
@testable import AcaiApp

/// The app ships in English, German and French, and only Xcode compiles `Localizable.xcstrings` —
/// so a missing identifier or a missing translation is invisible under `swift build` and surfaces
/// as raw text in a shipped build. These checks read the source and the catalog directly, which is
/// why they hold regardless of whether the catalog was compiled.
@Suite("Localization catalog")
struct LocalizationCatalogTests {

    private static let shippedLanguages = ["en", "de", "fr"]

    private let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/AcaiApp")

    /// One `.app("Identifier \(x)")` call site, with the source text of each interpolation.
    private struct Usage {
        let identifier: String
        let arguments: [String]
        let file: String

        var argumentCount: Int { arguments.count }
    }

    /// A localizable position that must never take a bare literal. The empty literal is the one
    /// exception — `Picker("", …)`/`Button("") { }` label an unlabelled control, not text.
    private static let localizablePrefixes = [
        "Text(", "Label(", "Button(", "Toggle(", "Picker(", "TextField(", "SecureField(",
        "Section(", "Menu(", "Link(", "NavigationLink(", "LabeledContent(", "DisclosureGroup(",
        "Stepper(", "ProgressView(", "ContentUnavailableView(", "TableColumn(", "GroupBox(",
        ".help(", ".navigationTitle(", ".accessibilityLabel(", ".accessibilityHint(",
        ".accessibilityValue(", ".alert(", ".confirmationDialog("
    ]

    /// The spellings that state what a `Text` holds. Anything else is an unmarked string.
    private static let textIntents = ["verbatim:", "localized:", ".app(", "image:"]

    // MARK: - Tests

    @Test("Every identifier used in the app exists in the catalog")
    func everyIdentifierIsInTheCatalog() throws {
        let strings = try catalogStrings()
        for usage in usages() {
            let matches = strings.keys.filter {
                $0 == usage.identifier || $0.hasPrefix(usage.identifier + " %")
            }
            #expect(
                matches.count == 1,
                "\(usage.file): '\(usage.identifier)' matches \(matches.count) catalog keys, expected 1"
            )
        }
    }

    @Test("A call site passes exactly as many arguments as its catalog key has placeholders")
    func argumentCountsMatchPlaceholders() throws {
        let strings = try catalogStrings()
        for usage in usages() {
            let key = strings.keys.first { $0 == usage.identifier || $0.hasPrefix(usage.identifier + " %") }
            guard let key else { continue }
            let placeholders = FormatArguments(key).byPosition.count
            #expect(
                placeholders == usage.argumentCount,
                """
                \(usage.file): '\(usage.identifier)' passes \(usage.argumentCount) arguments, \
                catalog key expects \(placeholders)
                """
            )
        }
    }

    @Test("Every localization formats its arguments exactly as the key declares them")
    func specifiersMatchTheKey() throws {
        let strings = try catalogStrings()
        for (key, entry) in strings {
            let declared = FormatArguments(key)
            guard !declared.byPosition.isEmpty else { continue }
            for language in Self.shippedLanguages {
                for format in formats(of: entry, language) {
                    let actual = FormatArguments(format.value, substitutions: format.substitutions)
                    #expect(
                        actual == declared,
                        """
                        \(language) '\(key)': value '\(format.value)' formats \(actual), \
                        the key declares \(declared)
                        """
                    )
                    #expect(
                        actual.strayPercents == 0,
                        """
                        \(language) '\(key)': value '\(format.value)' has a bare % — the formatter \
                        swallows it, so a literal percent sign must be written %%
                        """
                    )
                }
            }
        }
    }

    /// The key a call site looks up is built from the *type* it interpolates — an `Int` renders
    /// `%lld`, so a key written `%@` is never found and the identifier reaches the screen raw. Only
    /// the arguments source text alone proves to be integers are checked here; the rest is on the
    /// Xcode build, which is the only thing that compiles the catalog.
    @Test("An integer argument reaches a catalog key that formats integers")
    func integerArgumentsUseIntegerSpecifiers() throws {
        let strings = try catalogStrings()
        for usage in usages() {
            let key = strings.keys.first { $0 == usage.identifier || $0.hasPrefix(usage.identifier + " %") }
            guard let key else { continue }
            let declared = FormatArguments(key).byPosition
            for (offset, argument) in usage.arguments.enumerated() where isInteger(argument) {
                let specifier = declared[offset + 1]
                #expect(
                    specifier == "lld" || specifier == "d",
                    """
                    \(usage.file): '\(usage.identifier)' passes the integer '\(argument)', \
                    but '\(key)' formats argument \(offset + 1) as %\(specifier ?? "")
                    """
                )
            }
        }
    }

    /// Whether an interpolation is an integer on its source text alone — no type inference.
    private func isInteger(_ argument: String) -> Bool {
        argument.wholeMatch(of: /-?\d+/) != nil
            || argument.hasSuffix(".count")
            || argument.hasPrefix("Int(")
            || argument.contains(/\?\?\s*-?\d+$/)
    }

    /// `Text(someString)` renders whatever it is handed and reads the same whether the string is
    /// chrome that should have been translated or content that must not be. Spelling the intent out
    /// — `verbatim:` for content, `localized:`/`.app` for chrome — is what makes the difference
    /// visible to a reader and checkable here.
    @Test("Every Text says whether its content is localized or verbatim")
    func everyTextDeclaresItsIntent() throws {
        for file in swiftFiles() {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            var searched = source.startIndex
            while let start = source.range(of: "Text(", range: searched..<source.endIndex) {
                searched = start.upperBound
                if start.lowerBound > source.startIndex {
                    let before = source[source.index(before: start.lowerBound)]
                    guard !(before.isLetter || before == "." || before == "_") else { continue }
                }
                let argument = call(in: source, from: start.upperBound)
                    .drop { $0.isWhitespace }
                guard !argument.hasPrefix("\"") else { continue }
                let styled = argument.contains("format:") || argument.contains("style:")
                #expect(
                    Self.textIntents.contains(where: argument.hasPrefix) || styled,
                    """
                    \(file.lastPathComponent): Text(\(argument.prefix(40))…) says nothing about its \
                    content — use Text(verbatim:) for content, Text(localized:)/.app for chrome
                    """
                )
            }
        }
    }

    @Test("No catalog entry is orphaned")
    func noOrphanedEntries() throws {
        let strings = try catalogStrings()
        let used = Set(usages().map(\.identifier))
        for key in strings.keys {
            let identifier = key.prefix { $0 != " " }
            #expect(used.contains(String(identifier)), "'\(key)' is in the catalog but nothing uses it")
        }
    }

    @Test("Every entry is translated into every shipped language")
    func everyEntryIsTranslated() throws {
        for (key, entry) in try catalogStrings() {
            let present = languages(in: entry)
            let missing = Set(Self.shippedLanguages).subtracting(present).sorted()
            #expect(missing.isEmpty, "'\(key)' is missing \(missing.joined(separator: ", "))")
        }
    }

    /// One English string must not come out two different ways in the same language — the reader
    /// sees the same control named differently on two screens.
    @Test("A term is translated the same way everywhere", arguments: ["de", "fr"])
    func translationsAreConsistent(_ language: String) throws {
        var byEnglish: [String: [String: [String]]] = [:]
        for (key, entry) in try catalogStrings() {
            guard let english = text(of: entry, "en"), let translated = text(of: entry, language) else { continue }
            byEnglish[english, default: [:]][translated, default: []].append(key)
        }
        for (english, renderings) in byEnglish where renderings.count > 1 {
            let detail = renderings
                .sorted { $0.key < $1.key }
                .map { "\"\($0.key)\" (\($0.value.sorted().joined(separator: ", ")))" }
                .joined(separator: " vs ")
            Issue.record("\(language): \"\(english)\" is translated \(renderings.count) ways — \(detail)")
        }
    }

    /// The diagram kinds are one family: translating some names and leaving others in English reads
    /// as an oversight. A name may stay English only as a deliberate loanword, listed here.
    private static let loanwordDiagramNames: [String: Set<String>] = [
        "de": ["DiagramType.Hotspots"],
        "fr": []
    ]

    @Test("Diagram names are translated as one family", arguments: ["de", "fr"])
    func diagramNamesAgree(_ language: String) throws {
        let strings = try catalogStrings()
        let loanwords = Self.loanwordDiagramNames[language] ?? []
        let names = strings.keys.filter { $0.hasPrefix("DiagramType.") }
        var untranslated: [String] = []
        var translated: [String] = []
        for key in names.sorted() {
            guard let entry = strings[key], let english = text(of: entry, "en"),
                  let localized = text(of: entry, language) else { continue }
            guard !loanwords.contains(key) else { continue }
            if localized == english { untranslated.append(key) } else { translated.append(key) }
        }
        #expect(
            untranslated.isEmpty || translated.isEmpty,
            """
            \(language): \(translated.count) diagram names are translated but \
            \(untranslated.joined(separator: ", ")) stayed English — translate them too, or add \
            them to `loanwordDiagramNames` if that is deliberate
            """
        )
    }

    @Test("No string reaches the interface as a bare literal")
    func noBareLiterals() throws {
        for file in swiftFiles() {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for prefix in Self.localizablePrefixes {
                var searched = source.startIndex
                while let start = source.range(of: prefix, range: searched..<source.endIndex) {
                    searched = start.upperBound
                    // `Label(` must be the whole word, not the tail of `chartXAxisLabel(`.
                    let isWholeWord = prefix.hasPrefix(".") || start.lowerBound == source.startIndex
                        || !(source[source.index(before: start.lowerBound)].isLetter
                             || source[source.index(before: start.lowerBound)] == ".")
                    guard isWholeWord else { continue }
                    // The literal may sit on the next line — a call broken after its paren is the
                    // same violation.
                    var argument = source[start.upperBound...].drop { $0.isWhitespace }
                    guard argument.first == "\"" else { continue }
                    argument = argument.dropFirst()
                    #expect(
                        argument.first == "\"",
                        "\(file.lastPathComponent): \(prefix)\"…\") takes a bare literal — use .app(\"…\")"
                    )
                }
            }
        }
    }
}

// MARK: - Catalog and Source Reading

extension LocalizationCatalogTests {

    // MARK: - Catalog

    private func catalogStrings() throws -> [String: [String: Any]] {
        let url = sourceRoot.appendingPathComponent("Resources/Localizable.xcstrings")
        let object = try JSONSerialization.jsonObject(with: try Data(contentsOf: url))
        let catalog = try #require(object as? [String: Any])
        return try #require(catalog["strings"] as? [String: [String: Any]])
    }

    private func languages(in entry: [String: Any]) -> Set<String> {
        Set((entry["localizations"] as? [String: Any])?.keys ?? [:].keys)
    }

    /// The entry's text in one language: either its flat value, or a plural's `other` form.
    private func text(of entry: [String: Any], _ language: String) -> String? {
        guard let localizations = entry["localizations"] as? [String: Any],
              let localization = localizations[language] as? [String: Any] else { return nil }
        if let unit = localization["stringUnit"] as? [String: Any] { return unit["value"] as? String }
        guard let variations = localization["variations"] as? [String: Any],
              let plural = variations["plural"] as? [String: Any],
              let other = plural["other"] as? [String: Any],
              let unit = other["stringUnit"] as? [String: Any] else { return nil }
        return unit["value"] as? String
    }

    /// One concrete format string of a localization, with the substitutions that resolve its
    /// `%#@name@` tokens. A plural entry has one per plural form; every form has to agree.
    private struct LocalizedFormat {
        let value: String
        let substitutions: [String: [String: Any]]
    }

    /// Every format string a localization can produce — its flat value, or one per plural form.
    private func formats(of entry: [String: Any], _ language: String) -> [LocalizedFormat] {
        guard let localizations = entry["localizations"] as? [String: Any],
              let localization = localizations[language] as? [String: Any] else { return [] }
        let substitutions = localization["substitutions"] as? [String: [String: Any]] ?? [:]
        if let unit = localization["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
            return [LocalizedFormat(value: value, substitutions: substitutions)]
        }
        guard let variations = localization["variations"] as? [String: Any],
              let plural = variations["plural"] as? [String: Any] else { return [] }
        return plural.values.compactMap { form in
            guard let form = form as? [String: Any], let unit = form["stringUnit"] as? [String: Any],
                  let value = unit["value"] as? String else { return nil }
            return LocalizedFormat(value: value, substitutions: substitutions)
        }
    }

    // MARK: - Source

    private func swiftFiles() -> [URL] {
        guard let walker = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil) else {
            return []
        }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// Every `.app("…")` in the module, with the number of interpolated arguments it passes.
    private func usages() -> [Usage] {
        var usages: [Usage] = []
        for file in swiftFiles() {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            var remainder = Substring(source)
            while let start = remainder.range(of: ".app(\"") {
                remainder = remainder[start.upperBound...]
                guard let end = remainder.firstIndex(of: "\"") else { break }
                let literal = remainder[..<end]
                let identifier = literal.prefix { $0 != " " }
                usages.append(
                    Usage(
                        identifier: String(identifier),
                        arguments: interpolations(in: literal),
                        file: file.lastPathComponent
                    )
                )
                remainder = remainder[end...]
            }
        }
        return usages
    }

    /// The source text of each `\(…)` in a string literal, paren-balanced so a nested call stays
    /// whole.
    private func interpolations(in literal: Substring) -> [String] {
        var arguments: [String] = []
        var remainder = literal
        while let start = remainder.range(of: "\\(") {
            remainder = remainder[start.upperBound...]
            var depth = 1
            var end = remainder.startIndex
            while end < remainder.endIndex, depth > 0 {
                if remainder[end] == "(" { depth += 1 }
                if remainder[end] == ")" { depth -= 1 }
                if depth > 0 { end = remainder.index(after: end) }
            }
            arguments.append(String(remainder[..<end]))
            guard end < remainder.endIndex else { break }
            remainder = remainder[remainder.index(after: end)...]
        }
        return arguments
    }

    /// The source text between a `(` at `start` and its matching `)`.
    private func call(in source: String, from start: String.Index) -> Substring {
        var depth = 1
        var end = start
        while end < source.endIndex, depth > 0 {
            if source[end] == "(" { depth += 1 }
            if source[end] == ")" { depth -= 1 }
            if depth > 0 { end = source.index(after: end) }
        }
        return source[start..<end]
    }

}
