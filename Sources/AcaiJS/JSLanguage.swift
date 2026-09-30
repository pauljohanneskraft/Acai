import AcaiCore

// TypeScript and JavaScript identities + quirks. One target hosts both because a single
// `JSCodeParser` (toggled by `isTypeScript`) parses both, sharing one configuration.

extension CodeArtifact.SourceLanguage {
    public static let typeScript = CodeArtifact.SourceLanguage(rawValue: "typeScript")
    public static let javaScript = CodeArtifact.SourceLanguage(rawValue: "javaScript")
}

extension JSCodeParser {
    public var configuration: LanguageConfiguration {
        LanguageConfiguration(
            primitiveTypeNames: [
                "string", "number", "boolean", "undefined", "null", "symbol", "bigint",
                "unknown", "never", "object", "any", "void",
                "Object", "Number", "String", "Boolean", "Promise", "Function", "Date"
            ],
            collectionTypeNames: [
                "Array", "Map", "Set", "WeakMap", "WeakSet", "Record", "ReadonlyArray"
            ],
            excludedDirectories: ["node_modules", "dist", "build", ".next", "out"],
            // React/Angular component lifecycle callbacks are invoked by the framework, not by
            // resolvable call sites.
            entryPointMarkers: EntryPointMarkers(
                annotations: ["component", "injectable", "input", "output", "hostlistener"],
                methodNames: [
                    "main", "componentdidmount", "componentwillunmount", "componentdidupdate",
                    "render", "ngoninit", "ngondestroy", "ngonchanges"
                ])
        )
    }
}
