import Foundation
import MCP
import UMLConformance
import UMLCore
import UMLLibrary

/// Dispatches MCP tool calls to the engine, using the shared `SnapshotCache` for memoization.
struct ToolDispatcher: Sendable {
    let cache: SnapshotCache

    init(cache: SnapshotCache) {
        self.cache = cache
    }

    // MARK: - Dispatch

    func dispatch(name: String, arguments: [String: Value]?) async -> CallTool.Result {
        do {
            let args = arguments ?? [:]
            switch name {
            case "uml_analyze":
                return try await handleAnalyze(args)
            case "uml_metrics":
                return try await handleMetrics(args)
            case "uml_cycles":
                return try await handleCycles(args)
            case "uml_smells":
                return try await handleSmells(args)
            case "uml_inspect":
                return try await handleInspect(args)
            case "uml_check":
                return try await handleCheck(args)
            default:
                return errorResult("Unknown tool: \(name)")
            }
        } catch {
            return errorResult(String(describing: error))
        }
    }

    // MARK: - Tool Handlers

    private func handleAnalyze(_ args: [String: Value]) async throws -> CallTool.Result {
        let path = try requireString(args, key: "path")
        let artifact = try await cache.artifact(at: path)
        let summary = AnalyzeSummary(artifact: artifact)
        return jsonResult(summary)
    }

    private func handleMetrics(_ args: [String: Value]) async throws -> CallTool.Result {
        let path = try requireString(args, key: "path")
        let artifact = try await cache.artifact(at: path)
        let metrics = artifact.computeMetrics()
        return encodableResult(metrics)
    }

    private func handleCycles(_ args: [String: Value]) async throws -> CallTool.Result {
        let path = try requireString(args, key: "path")
        let artifact = try await cache.artifact(at: path)
        let scopeRaw = args["scope"]?.stringValue ?? "all"
        let finder = CycleFinder(
            artifact: artifact,
            annotationStereotypes: artifact.standardLanguageConfiguration.annotationStereotypes)

        let scopes: [CycleFinder.Scope] = scopeRaw == "all" ? [.modules, .types]
            : [scopeRaw == "modules" ? .modules : .types]
        let cycles = scopes.flatMap { finder.cycles(scope: $0) }
        let payload = cycles.map { CyclePayload(scope: $0.scope.rawValue, members: $0.members) }
        return encodableResult(payload)
    }

    private func handleSmells(_ args: [String: Value]) async throws -> CallTool.Result {
        let path = try requireString(args, key: "path")
        let artifact = try await cache.artifact(at: path)
        let metrics = artifact.computeMetrics()
        let smells = detectSmells(metrics: metrics, artifact: artifact)
        return encodableResult(smells)
    }

    private func handleInspect(_ args: [String: Value]) async throws -> CallTool.Result {
        let path = try requireString(args, key: "path")
        let typeName = try requireString(args, key: "type_name")
        let artifact = try await cache.artifact(at: path)
        let flat = flattenTypes(artifact.types)
        guard let match = flat.first(where: { $0.qualifiedName == typeName || $0.name == typeName }) else {
            return errorResult("Type '\(typeName)' not found in the analyzed codebase.")
        }
        let metrics = artifact.computeMetrics()
        let typeMetric = metrics.types.first { $0.id == match.id }
        let info = TypeInspection(declaration: match, metric: typeMetric, artifact: artifact)
        return jsonResult(info)
    }

    private func handleCheck(_ args: [String: Value]) async throws -> CallTool.Result {
        let path = try requireString(args, key: "path")
        let rulesPath = try requireString(args, key: "rules")
        let artifact = try await cache.artifact(at: path)
        let ruleSet = try ConformanceRules.loadFromFile(at: rulesPath)
        let evaluator = ConformanceEvaluator(
            rules: ruleSet,
            annotationStereotypes: artifact.standardLanguageConfiguration.annotationStereotypes)
        let report = evaluator.evaluate(artifact)
        let reportText: String
        if report.violations.isEmpty {
            reportText = "Conformance OK — \(report.checkedRuleCount) rule(s) checked, no violations."
        } else {
            let lines = report.violations.map { violation -> String in
                let prefix = violation.source.map { "\($0.filePath):\($0.line): " } ?? ""
                return "\(prefix)\(violation.ruleKind): \(violation.message)"
            }
            reportText = lines.joined(separator: "\n")
                + "\n\n\(report.violations.count) violation(s) across \(report.checkedRuleCount) rule(s)."
        }
        let payload = CheckPayload(passing: report.isPassing, report: reportText)
        return encodableResult(payload)
    }

    // MARK: - Helpers

    private func requireString(_ args: [String: Value], key: String) throws -> String {
        guard let value = args[key]?.stringValue, !value.isEmpty else {
            throw MCPToolError.missingArgument(key)
        }
        return value
    }

    private func errorResult(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
    }

    private func encodableResult<T: Encodable>(_ value: T) -> CallTool.Result {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value), let json = String(data: data, encoding: .utf8) else {
            return errorResult("Failed to encode result as JSON.")
        }
        return CallTool.Result(content: [.text(text: json, annotations: nil, _meta: nil)])
    }

    private func jsonResult<T: Encodable>(_ value: T) -> CallTool.Result {
        encodableResult(value)
    }
}

// MARK: - Payload Types

private struct CyclePayload: Codable {
    var scope: String
    var members: [String]
}

private struct CheckPayload: Codable {
    var passing: Bool
    var report: String
}

/// Lightweight summary returned by `uml_analyze` — enough for the LLM to confirm parsing succeeded
/// and decide which follow-up tools to invoke, without dumping the full artifact.
private struct AnalyzeSummary: Codable {
    var totalTypes: Int
    var totalRelationships: Int
    var languages: [String]
    var modules: [String]

    init(artifact: CodeArtifact) {
        let flat = flattenTypes(artifact.types)
        let resolver = ModuleResolver.standard
        self.totalTypes = flat.count
        self.totalRelationships = artifact.relationships.count
        self.languages = Array(Set(flat.compactMap { $0.location?.filePath }.map { filePath in
            artifact.metadata.sourceLanguage.rawValue
        }))
        self.modules = Array(Set(flat.compactMap {
            $0.location?.filePath
        }.map { resolver.productName(forFilePath: $0) })).sorted()
    }
}

/// Per-type inspection result with members, relationships, metrics and source location.
private struct TypeInspection: Codable {
    var name: String
    var qualifiedName: String
    var kind: String
    var location: String?
    var members: [MemberInfo]
    var incomingRelationships: [RelInfo]
    var outgoingRelationships: [RelInfo]
    var metric: MetricInfo?

    struct MemberInfo: Codable {
        var name: String
        var kind: String
        var accessLevel: String
    }

    struct RelInfo: Codable {
        var kind: String
        var other: String
    }

    struct MetricInfo: Codable {
        var fanIn: Int
        var fanOut: Int
        var weightedMethods: Int
        var depthOfInheritance: Int
        var numberOfChildren: Int
    }

    init(declaration: TypeDeclaration, metric: CodeMetrics.TypeMetric?, artifact: CodeArtifact) {
        self.name = declaration.name
        self.qualifiedName = declaration.qualifiedName
        self.kind = declaration.kind.rawValue
        if let loc = declaration.location {
            self.location = "\(loc.filePath):\(loc.line)"
        }
        self.members = declaration.members.map {
            MemberInfo(name: $0.name, kind: $0.kind.rawValue, accessLevel: $0.accessLevel.rawValue)
        }
        self.incomingRelationships = artifact.relationships
            .filter { $0.target == declaration.id }
            .map { RelInfo(kind: $0.kind.rawValue, other: $0.source) }
        self.outgoingRelationships = artifact.relationships
            .filter { $0.source == declaration.id }
            .map { RelInfo(kind: $0.kind.rawValue, other: $0.target) }
        if let metric {
            self.metric = MetricInfo(
                fanIn: metric.fanIn,
                fanOut: metric.fanOut,
                weightedMethods: metric.weightedMethods,
                depthOfInheritance: metric.depthOfInheritance,
                numberOfChildren: metric.numberOfChildren)
        }
    }
}
