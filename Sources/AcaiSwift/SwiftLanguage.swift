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
            // Swift Testing (`@Test`) and runtime-dispatched members (`@objc`, `@IBAction`) are invoked
            // by frameworks, not resolvable call sites; `main` is the process entry point. The
            // conformance markers below cover protocols declared outside the analysed sources
            // (ArgumentParser's commands, SwiftUI's view/scene builders, AppKit/UIKit's
            // representables) whose requirements the engine's witness exemption therefore can't see.
            // They are matched against the declaring type's supertypes rather than by name alone, so
            // an unrelated type's uncalled `run()` or `body` is still reported.
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
