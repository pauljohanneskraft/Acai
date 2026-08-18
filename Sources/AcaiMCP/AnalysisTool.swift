import MCP
import AcaiLibrary

/// One read-only analysis tool: a `name`, a trigger-shaped `description` (what an agent reads when
/// deciding to reach for it), a JSON input schema, and a `run` returning the report as a `Value`.
protocol AnalysisTool: Sendable {
    var name: String { get }
    var description: String { get }
    var inputSchema: Value { get }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput
}

extension AnalysisTool {
    func resolveArtifact(
        _ arguments: ToolArguments, _ cache: AnalysisSnapshotCache
    ) async throws -> CodeArtifact {
        try await cache.artifact(
            path: arguments.requiredString("path"),
            languageNames: arguments.stringArray("languages"),
            refresh: try arguments.bool("refresh") ?? false)
    }

    /// Drops each language's generated types unless the call passes `includeGenerated: true`, matching
    /// the CLI's `--include-generated`. (`QualityTool` filters via its rules' `includeGeneratedTypes`
    /// instead, so it uses `resolveArtifact` directly rather than this.)
    func analysisArtifact(
        _ arguments: ToolArguments, _ cache: AnalysisSnapshotCache
    ) async throws -> CodeArtifact {
        let artifact = try await resolveArtifact(arguments, cache)
        let include = try arguments.bool("includeGenerated") ?? false
        return include ? artifact : artifact.filteringGeneratedTypes(using: artifact.standardLanguageResolver)
    }

    var generatedScopeProperty: [String: Value] {
        [
            "includeGenerated": [
                "type": "boolean",
                "description": "Include machine-generated types in the analysis (default false: excluded)."
            ]
        ]
    }

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

    /// Parses a `"type:Name"` / `"module:Name"` scope string (whole-codebase when absent), mapping a
    /// parse failure onto `invalidParams`.
    func resolvedCallGraphScope(_ raw: String?) throws -> CallGraphScope {
        do {
            return try CallGraphScopeOption(raw: raw).resolved()
        } catch let error as DiagramRequestError {
            throw MCPError.invalidParams(error.message)
        }
    }

    /// Absent facets stay `nil`, so a call with no selector arguments matches every type.
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
