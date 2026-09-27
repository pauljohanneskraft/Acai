import MCP
import AcaiLibrary

/// `acai_inspect` — enumerates types and their members filtered by a selector + member facets, each
/// row carrying `file:line`. Mirrors `acai inspect`.
struct InspectTool: AnalysisTool {
    let name = "acai_inspect"
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
        let health = HealthCheck(artifact: artifact).summary
        if try arguments.bool("enums") ?? false {
            let entries = EnumInventory(artifact: artifact).entries
            return .json(try Value(EnumInventoryPayload(enums: entries, health: health)))
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
        return .json(try Value(InspectPayload(types: rows, health: health)))
    }

    private struct InspectPayload: Codable {
        var types: [TypeQuery.TypeRow]
        var health: HealthCheck.Summary
    }

    private struct EnumInventoryPayload: Codable {
        var enums: [EnumInventory.Entry]
        var health: HealthCheck.Summary
    }
}
