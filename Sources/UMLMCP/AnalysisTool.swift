import MCP
import UMLLibrary

/// One read-only analysis tool. Every tool is an instantiable value conforming to this — its `name`,
/// its trigger-shaped `description` (the autonomous surface an agent reads when deciding to reach for
/// it), its JSON input schema, and a `run` that returns the report already encoded as a `Value`. The
/// shared helpers below (`resolveArtifact`, schema fragments, selector mapping) keep each tool tiny.
protocol AnalysisTool: Sendable {
    var name: String { get }
    var description: String { get }
    var inputSchema: Value { get }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput
}

extension AnalysisTool {
    /// The cached, enriched artifact for this call's `path` (+ optional `languages` / `refresh`).
    /// Every analysis tool shares these three inputs, so resolving them lives here once.
    func resolveArtifact(
        _ arguments: ToolArguments, _ cache: AnalysisSnapshotCache
    ) async throws -> CodeArtifact {
        try await cache.artifact(
            path: arguments.requiredString("path"),
            languageNames: arguments.stringArray("languages"),
            refresh: try arguments.bool("refresh") ?? false)
    }

    /// The `path` / `languages` / `refresh` schema fragment every analysis tool shares.
    var baseProperties: [String: Value] {
        [
            "path": [
                "type": "string",
                "description": "Path to the project root to analyze (absolute or relative)."
            ],
            "languages": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Optional language filter (e.g. swift, kotlin, python). Empty means all."
            ],
            "refresh": [
                "type": "boolean",
                "description": "Re-analyze instead of reusing the cached snapshot for this path."
            ]
        ]
    }

    /// The type-`Selector` schema fragment shared by the type-filtering tools (`inspect`, `smells`).
    var selectorProperties: [String: Value] {
        [
            "module": ["type": "string", "description": "Only types whose module matches this glob (*, ?)."],
            "type": ["type": "string", "description": "Only types whose id / qualified name matches this glob."],
            "kind": ["type": "string", "description": "Only types of this kind (e.g. class, protocol, struct)."],
            "minAccess": ["type": "string", "description": "Only types with at least this visibility (e.g. public)."],
            "stereotype": ["type": "string", "description": "Only types carrying this UML stereotype."],
            "annotation": ["type": "string", "description": "Only types carrying this annotation marker."],
            "minMembers": ["type": "integer", "description": "Only types with at least this many members (god types)."],
            "minNesting": ["type": "integer", "description": "Only types nested at least this deep."]
        ]
    }

    /// Builds an object schema from `baseProperties` plus any tool-specific `extraProperties`, marking
    /// `required` keys. Keeps every tool's `inputSchema` a one-liner.
    func objectSchema(extraProperties: [String: Value] = [:], required: [String] = ["path"]) -> Value {
        var properties = baseProperties
        for (key, value) in extraProperties {
            properties[key] = value
        }
        return [
            "type": "object",
            "properties": .object(properties),
            "required": .array(required.map(Value.string))
        ]
    }

    /// Resolves a `"type:Name"` / `"module:Name"` scope string (whole-codebase when absent) via the
    /// shared diagram-layer parser, mapping its error onto `invalidParams`.
    func resolvedCallGraphScope(_ raw: String?) throws -> CallGraphScope {
        do {
            return try CallGraphScopeOption(raw: raw).resolved()
        } catch let error as DiagramRequestError {
            throw MCPError.invalidParams(error.message)
        }
    }

    /// Maps the shared selector arguments onto the engine `Selector`. Absent facets stay `nil`, so a
    /// call with no selector arguments matches every type; a present numeric facet of the wrong JSON
    /// type throws `invalidParams`.
    func selector(from arguments: ToolArguments) throws -> Selector {
        Selector(
            module: arguments.string("module"),
            typeGlob: arguments.string("type"),
            stereotype: arguments.string("stereotype"),
            annotation: arguments.string("annotation"),
            minimumAccess: arguments.string("minAccess").flatMap(AccessLevel.init(rawValue:)),
            kind: arguments.string("kind").flatMap(TypeKind.init(rawValue:)),
            minMembers: try arguments.int("minMembers"),
            minNesting: try arguments.int("minNesting"))
    }
}
