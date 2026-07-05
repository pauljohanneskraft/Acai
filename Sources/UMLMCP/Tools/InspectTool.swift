import MCP
import UMLLibrary

/// `uml_inspect` — enumerate types and their members filtered by a selector + member facets, each row
/// carrying `file:line`. The highest-leverage locator for an agent. Mirrors `uml inspect`.
struct InspectTool: AnalysisTool {
    let name = "uml_inspect"
    let description = """
        Enumerate types and members matching a selector, each with a file:line jump target. Answers \
        "where is type X / which public classes in module Y have a method with 4+ parameters?" without \
        grepping. Combine the type selector facets with member facets (memberKind, minParameters, …).
        """

    var inputSchema: Value {
        var properties = selectorProperties
        properties["memberKind"] = ["type": "string", "description": "Only members of this kind (method, property, …)."]
        properties["minParameters"] = ["type": "integer", "description": "Only members with at least N parameters."]
        properties["publicVars"] = ["type": "boolean", "description": "Only publicly-settable stored properties."]
        properties["overrides"] = ["type": "boolean", "description": "Only members that override an inherited member."]
        return objectSchema(extraProperties: properties)
    }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> Value {
        let artifact = try await resolveArtifact(arguments, cache)
        let rows = TypeQuery(
            artifact: artifact,
            selector: selector(from: arguments),
            members: MemberFilter(
                kind: arguments.string("memberKind").flatMap(MemberKind.init(rawValue:)),
                minParameters: arguments.int("minParameters"),
                isPublicVar: (arguments.bool("publicVars") ?? false) ? true : nil,
                isOverride: (arguments.bool("overrides") ?? false) ? true : nil),
            annotationStereotypes: artifact.standardLanguageConfiguration.annotationStereotypes
        ).rows
        return try Value(rows)
    }
}
