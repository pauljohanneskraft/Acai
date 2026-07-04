import UMLCore

// The Swift language's identity and quirks live here, in the Swift target — never in the
// agnostic engine. An external consumer adds a language exactly like this, from the outside.

extension CodeArtifact.SourceLanguage {
    public static let swift = CodeArtifact.SourceLanguage(rawValue: "swift")
}

extension SwiftCodeParser {
    public var configuration: LanguageConfiguration {
        LanguageConfiguration(
            primitiveTypeNames: [
                "Void", "Never", "Any", "AnyObject", "Self",
                "String", "Int", "Double", "Float", "Bool", "Character", "UInt",
                "Int8", "Int16", "Int32", "Int64", "UInt8", "UInt16", "UInt32", "UInt64",
                "CGFloat", "Data", "Date", "URL", "UUID", "Error", "Sendable", "Codable",
                "Equatable", "Hashable", "Comparable", "Identifiable", "CustomStringConvertible",
                "Optional"
            ],
            collectionTypeNames: [
                "Array", "Dictionary", "Set", "Sequence", "Collection"
            ],
            excludedDirectories: [".build", "DerivedData", "Pods", ".swiftpm"],
            // Swift Testing (`@Test`) and runtime-dispatched members (`@objc`, `@IBAction`) are invoked
            // by frameworks, not by resolvable call sites; `main` is the process entry point.
            entryPointMarkers: EntryPointMarkers(
                annotations: ["test", "objc", "ibaction", "main"],
                methodNames: ["main"])
        )
    }
}
