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

        if let directionStr = yaml["direction"] as? String,
           let dir = DiagramOptions.LayoutDirection(rawValue: directionStr) {
            self.layoutDirection = dir
        }

        if let themeStr = yaml["theme"] as? String {
            switch themeStr.lowercased() {
            case "dark":    self.theme = .dark
            case "default": self.theme = .default
            default: print("Warning: Unknown theme '\(themeStr)', using default.")
            }
        }

        if let groupStr = yaml["groupBy"] as? String {
            switch groupStr.lowercased() {
            case "file":      self.groupBy = .byFile
            case "namespace": self.groupBy = .byNamespace
            case "none":      self.groupBy = .none
            default: print("Warning: Unknown groupBy '\(groupStr)', using none.")
            }
        }

        if let v = yaml["showMembers"]             as? Bool { self.showMembers = v }
        if let v = yaml["showMemberTypes"]         as? Bool { self.showMemberTypes = v }
        if let v = yaml["showAccessLevelSymbols"]  as? Bool { self.showAccessLevelSymbols = v }
        if let v = yaml["showAnnotations"]         as? Bool { self.showAnnotations = v }
        if let v = yaml["showGenericParameters"]   as? Bool { self.showGenericParameters = v }
        if let v = yaml["fontName"]                as? String { self.fontName = v }
        if let v = yaml["fontSize"]                as? Int { self.fontSize = v }
    }
}
