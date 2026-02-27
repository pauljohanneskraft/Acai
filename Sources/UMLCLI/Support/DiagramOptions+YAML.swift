import ArgumentParser
import Foundation
import UMLDiagram
import UMLLibrary
import Yams

extension DiagramOptions {
    mutating func applyYAMLConfig(_ yamlString: String) throws {
        guard let yaml = try Yams.load(yaml: yamlString) as? [String: Any] else {
            throw ValidationError("Invalid YAML configuration. Expected a mapping at the top level.")
        }

        applyDirection(from: yaml)
        applyTheme(from: yaml)
        applyGroupBy(from: yaml)
        applyBooleanFlags(from: yaml)
        applyFontSettings(from: yaml)
    }

    // MARK: - Private Helpers

    private mutating func applyDirection(from yaml: [String: Any]) {
        if let directionStr = yaml["direction"] as? String,
           let dir = DiagramOptions.LayoutDirection(rawValue: directionStr) {
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
        if let value = yaml["showAnnotations"]         as? Bool { self.showAnnotations = value }
        if let value = yaml["showGenericParameters"]   as? Bool { self.showGenericParameters = value }
    }

    private mutating func applyFontSettings(from yaml: [String: Any]) {
        if let value = yaml["fontName"] as? String { self.fontName = value }
        if let value = yaml["fontSize"] as? Int { self.fontSize = value }
    }
}
