import MCP
import UMLLibrary

/// `uml_inspect` — enumerate types and their members filtered by a selector + member facets, each row
/// carrying `file:line`. The highest-leverage locator for an agent. Mirrors `uml inspect`.
struct InspectTool: AnalysisTool {
    let name = "uml_inspect"
    let description = """
        Enumerate types and members matching a selector, each with a file:line jump target. Answers \
        "where is type X / which public classes in module Y have a method with 4+ parameters?" without \
        grepping. Combine the type selector facets with member facets (memberKind, minParameters, …). \
        Set 'enums' to instead inventory enum-like types with their cases, raw and associated values.
        """

    var inputSchema: Value {
        var properties = selectorProperties
        properties["memberKind"] = ["type": "string", "description": "Only members of this kind (method, property, …)."]
        properties["minParameters"] = ["type": "integer", "description": "Only members with at least N parameters."]
        properties["publicVars"] = ["type": "boolean", "description": "Only publicly-settable stored properties."]
        properties["overrides"] = ["type": "boolean", "description": "Only members that override an inherited member."]
        properties["enums"] = ["type": "boolean", "description": "List enum cases with raw/associated values instead."]
        properties.merge(generatedScopeProperty) { $1 }
        return objectSchema(extraProperties: properties)
    }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        let artifact = try await analysisArtifact(arguments, cache)
        if try arguments.bool("enums") ?? false {
            return .json(try Value(EnumInventory(artifact: artifact).entries))
        }
        let rows = TypeQuery(
            artifact: artifact,
            selector: try selector(from: arguments),
            members: MemberFilter(
                kind: arguments.string("memberKind").flatMap(MemberKind.init(rawValue:)),
                minParameters: try arguments.int("minParameters"),
                isPublicVar: (try arguments.bool("publicVars") ?? false) ? true : nil,
                isOverride: (try arguments.bool("overrides") ?? false) ? true : nil),
            languageResolver: artifact.standardLanguageResolver
        ).rows
        return .json(try Value(rows))
    }
}
