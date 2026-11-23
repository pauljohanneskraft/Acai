import AcaiCore

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
            // Conformance markers stand in for requirements of protocols declared outside the analysed sources.
            entryPointMarkers: EntryPointMarkers(
                annotations: ["test", "objc", "ibaction", "main"],
                methodNames: ["main"],
                conformanceMembers: [
                    "ParsableCommand": ["run", "validate"],
                    "AsyncParsableCommand": ["run", "validate"],
                    "ParsableArguments": ["validate"],
                    "App": ["body"],
                    "Scene": ["body"],
                    "View": ["body"],
                    "ViewModifier": ["body"],
                    "Commands": ["body"],
                    "Shape": ["path"],
                    "PreferenceKey": ["reduce"],
                    "NSViewRepresentable": [
                        "makensview", "updatensview", "dismantlensview", "makecoordinator"],
                    "UIViewRepresentable": [
                        "makeuiview", "updateuiview", "dismantleuiview", "makecoordinator"],
                    "NSViewControllerRepresentable": [
                        "makensviewcontroller", "updatensviewcontroller",
                        "dismantlensviewcontroller", "makecoordinator"],
                    "UIViewControllerRepresentable": [
                        "makeuiviewcontroller", "updateuiviewcontroller",
                        "dismantleuiviewcontroller", "makecoordinator"]
                ]),
            // `CallSiteCollector` records a caller edge for every construction and project-type subscript.
            deadCodeMemberKinds: [.method, .initializer, .subscript]
        )
    }
}
