import Foundation
import MCP

/// All MCP tools exposed by the UML server. Each tool is read-only and returns JSON with `file:line`
/// location data where applicable.
enum MCPTools {
    static let all: [Tool] = [
        analyzeDefinition,
        metricsDefinition,
        cyclesDefinition,
        smellsDefinition,
        inspectDefinition,
        checkDefinition,
    ]

    // MARK: - Tool Definitions

    static let analyzeDefinition = Tool(
        name: "uml_analyze",
        description: """
            Parse a source directory and return a structural snapshot: types, relationships, \
            and module attribution. Use this first to confirm the project parses correctly \
            before running metrics or cycle detection.
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "path": .object([
                    "type": "string",
                    "description": "Absolute path to the project root directory to analyze.",
                ]),
            ]),
            "required": .array([.string("path")]),
        ]),
        annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
    )

    static let metricsDefinition = Tool(
        name: "uml_metrics",
        description: """
            Compute static-analysis metrics for a codebase: concept counts, per-module \
            coupling (Ca/Ce/instability/abstractness/distance-from-main-sequence), and \
            per-type OO metrics (DIT, NOC, WMC, fan-in, fan-out). Returns JSON. \
            Use to find god classes (high WMC + fan-out), unstable modules, and \
            over-coupled types.
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "path": .object([
                    "type": "string",
                    "description": "Absolute path to the project root directory.",
                ]),
            ]),
            "required": .array([.string("path")]),
        ]),
        annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
    )

    static let cyclesDefinition = Tool(
        name: "uml_cycles",
        description: """
            Detect dependency cycles (strongly-connected components) at module and/or type \
            scope. Returns JSON array of cycles. Use to find circular dependencies that \
            block safe refactoring or indicate layering violations.
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "path": .object([
                    "type": "string",
                    "description": "Absolute path to the project root directory.",
                ]),
                "scope": .object([
                    "type": "string",
                    "enum": .array([.string("modules"), .string("types"), .string("all")]),
                    "description": "Cycle scope: modules, types, or all (default).",
                ]),
            ]),
            "required": .array([.string("path")]),
        ]),
        annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
    )

    static let smellsDefinition = Tool(
        name: "uml_smells",
        description: """
            Detect architectural smells: god classes (high WMC + fan-out), shotgun surgery \
            candidates (high fan-in), feature envy (high efferent coupling), and unstable \
            abstractions (high distance from main sequence). Returns JSON with file:line \
            locations. Use to prioritize refactoring targets.
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "path": .object([
                    "type": "string",
                    "description": "Absolute path to the project root directory.",
                ]),
            ]),
            "required": .array([.string("path")]),
        ]),
        annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
    )

    static let inspectDefinition = Tool(
        name: "uml_inspect",
        description: """
            Inspect a specific type by name: returns its members, relationships, metrics, \
            and location. Use to understand a type's role before changing it — see what \
            depends on it (fan-in) and what it depends on (fan-out).
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "path": .object([
                    "type": "string",
                    "description": "Absolute path to the project root directory.",
                ]),
                "type_name": .object([
                    "type": "string",
                    "description": "Name or qualified name of the type to inspect.",
                ]),
            ]),
            "required": .array([.string("path"), .string("type_name")]),
        ]),
        annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
    )

    static let checkDefinition = Tool(
        name: "uml_check",
        description: """
            Check the codebase against a declarative architecture rules file (YAML). \
            Validates forbidden dependencies, dependency cycles, layering, metric budgets, \
            and stereotype contracts. Returns pass/fail with violation details. Use as an \
            architecture fitness function.
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "path": .object([
                    "type": "string",
                    "description": "Absolute path to the project root directory.",
                ]),
                "rules": .object([
                    "type": "string",
                    "description": "Path to the YAML architecture rules file.",
                ]),
            ]),
            "required": .array([.string("path"), .string("rules")]),
        ]),
        annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
    )
}
