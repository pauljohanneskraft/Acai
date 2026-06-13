import ArgumentParser
import Foundation
import UMLCore
import UMLDiagram
import UMLLibrary
import Yams

extension ClassDiagramOptions {
    mutating func applyYAMLConfig(_ yamlString: String) throws {
        guard let yaml = try Yams.load(yaml: yamlString) as? [String: Any] else {
            throw ValidationError("Invalid YAML configuration. Expected a mapping at the top level.")
        }

        applyDirection(from: yaml)
        applyTheme(from: yaml)
        applyGroupBy(from: yaml)
        applyBooleanFlags(from: yaml)
        applyFontSettings(from: yaml)
        applyFocus(from: yaml)
    }

    // MARK: - Private Helpers

    private mutating func applyDirection(from yaml: [String: Any]) {
        if let directionStr = yaml["direction"] as? String,
           let dir = ClassDiagramOptions.LayoutDirection(rawValue: directionStr) {
            self.layoutDirection = dir
        }
    }

    private mutating func applyTheme(from yaml: [String: Any]) {
        guard let themeStr = yaml["theme"] as? String else { return }
        switch themeStr.lowercased() {
        case "dark":
            self.theme = .dark
        case "default":
            self.theme = .default
        default:
            print("Warning: Unknown theme '\(themeStr)', using default.")
        }
    }

    private mutating func applyGroupBy(from yaml: [String: Any]) {
        guard let groupStr = yaml["groupBy"] as? String else { return }
        switch groupStr.lowercased() {
        case "file":
            self.groupBy = .byFile
        case "namespace":
            self.groupBy = .byNamespace
        case "none":
            self.groupBy = .none
        default:
            print("Warning: Unknown groupBy '\(groupStr)', using none.")
        }
    }

    private mutating func applyBooleanFlags(from yaml: [String: Any]) {
        if let value = yaml["showMembers"]             as? Bool { self.showMembers = value }
        if let value = yaml["showMemberTypes"]         as? Bool { self.showMemberTypes = value }
        if let value = yaml["showAccessLevelSymbols"]  as? Bool { self.showAccessLevelSymbols = value }
        if let value = yaml["showGenericParameters"]   as? Bool { self.showGenericParameters = value }
    }

    private mutating func applyFontSettings(from yaml: [String: Any]) {
        if let value = yaml["fontName"] as? String { self.fontName = value }
        if let value = yaml["fontSize"] as? Int { self.fontSize = value }
    }

    /// Parses a `focus:` sub-mapping (`root`, `depth`, `direction`, `relationships`,
    /// `interconnections`). Requires `root`; otherwise the block is ignored.
    private mutating func applyFocus(from yaml: [String: Any]) {
        guard let focusYaml = yaml["focus"] as? [String: Any],
              let root = focusYaml["root"] as? String else { return }

        let direction = (focusYaml["direction"] as? String)
            .flatMap { FocusConfiguration.Direction(rawValue: $0.lowercased()) } ?? .dependencies

        let kinds = (focusYaml["relationships"] as? [Any])?
            .compactMap { ($0 as? String).flatMap { Relationship.Kind(rawValue: $0.lowercased()) } }
        let includedKinds = (kinds?.isEmpty == false) ? Set(kinds!) : Set(Relationship.Kind.allCases)

        self.focus = FocusConfiguration(
            rootTypeName: root,
            maxDepth: focusYaml["depth"] as? Int,
            direction: direction,
            includedRelationshipKinds: includedKinds,
            includeInterconnections: focusYaml["interconnections"] as? Bool ?? true
        )
    }
}
