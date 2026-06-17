// The language-agnostic engine never hard-codes a language's quirks. Instead, each
// `CodeParser` vends a `LanguageConfiguration` describing the reference data that the
// generic pipeline needs (type-name classification, framework stereotypes, generated-code
// filtering, build-output directories). The agnostic targets receive this purely by
// parameter injection, so a brand-new language can be added entirely from the outside.

/// A bare prefix/suffix rule used to recognise machine-generated type names without a closure.
///
/// A pattern matches when every set bound holds; an all-`nil` pattern matches nothing (so an
/// empty rule never silently swallows every type).
public struct NamePattern: Sendable, Equatable, Hashable, Codable {
    public var prefix: String?
    public var suffix: String?

    public init(prefix: String? = nil, suffix: String? = nil) {
        self.prefix = prefix
        self.suffix = suffix
    }

    public func matches(_ name: String) -> Bool {
        guard prefix != nil || suffix != nil else { return false }
        if let prefix, !name.hasPrefix(prefix) { return false }
        if let suffix, !name.hasSuffix(suffix) { return false }
        return true
    }
}

/// Declarative description of a language's code-generation output, so the agnostic renderer can
/// offer a "hide generated types" affordance for any language without knowing the language.
///
/// `displayName`/`explanation` are surfaced verbatim in UI (e.g. the app's inspector toggle), and
/// matching is expressed as data (`fileSuffixes` + `typeNamePatterns`) rather than code.
public struct GeneratedCodeFilter: Sendable, Equatable, Hashable, Codable {
    /// Human-readable label for the affordance, e.g. `"Dart Generated Types"`.
    public var displayName: String
    /// One-line explanation for the affordance, e.g. `"Hides types from .freezed.dart, .g.dart…"`.
    public var explanation: String
    /// File-name suffixes emitted by the language's code generators, e.g. `[".freezed.dart"]`.
    public var fileSuffixes: [String]
    /// Naming patterns emitted by the language's code generators, e.g. `prefix "_$"`.
    public var typeNamePatterns: [NamePattern]

    public init(
        displayName: String,
        explanation: String,
        fileSuffixes: [String] = [],
        typeNamePatterns: [NamePattern] = []
    ) {
        self.displayName = displayName
        self.explanation = explanation
        self.fileSuffixes = fileSuffixes
        self.typeNamePatterns = typeNamePatterns
    }

    /// `true` when `path` names a file produced by this language's code generators.
    public func matchesFile(_ path: String) -> Bool {
        fileSuffixes.contains { path.hasSuffix($0) }
    }

    /// `true` when `typeName` follows one of this language's code-generation naming patterns.
    public func matchesTypeName(_ typeName: String) -> Bool {
        typeNamePatterns.contains { $0.matches(typeName) }
    }
}

/// The per-language reference data the agnostic pipeline consumes by injection. A parser supplies
/// its own; everything defaults empty so non-language code (and external parsers that don't care)
/// keep working unchanged.
public struct LanguageConfiguration: Sendable, Equatable, Hashable, Codable {
    /// Type names treated as built-in scalars — never drawn as a related/external node.
    public var primitiveTypeNames: Set<String>
    /// Container type names whose element relationship is an aggregation (`*` multiplicity).
    public var collectionTypeNames: Set<String>
    /// Framework annotation (bare, lowercased name) → UML stereotype, e.g. `"entity": "entity"`.
    public var annotationStereotypes: [String: String]
    /// How to recognise this language's generated code, or `nil` when it has none.
    public var generatedCodeFilter: GeneratedCodeFilter?
    /// Build-output / dependency directories to skip while collecting this language's sources.
    public var excludedDirectories: Set<String>

    public init(
        primitiveTypeNames: Set<String> = [],
        collectionTypeNames: Set<String> = [],
        annotationStereotypes: [String: String] = [:],
        generatedCodeFilter: GeneratedCodeFilter? = nil,
        excludedDirectories: Set<String> = []
    ) {
        self.primitiveTypeNames = primitiveTypeNames
        self.collectionTypeNames = collectionTypeNames
        self.annotationStereotypes = annotationStereotypes
        self.generatedCodeFilter = generatedCodeFilter
        self.excludedDirectories = excludedDirectories
    }

    public func isPrimitive(_ name: String) -> Bool { primitiveTypeNames.contains(name) }
    public func isCollectionType(_ name: String) -> Bool { collectionTypeNames.contains(name) }
}
