import Foundation
import UMLCore
import UMLLibrary

/// Architectural smell detection derived from `CodeMetrics`. Produces a JSON-serializable array of
/// findings with file:line locations and severity. The thresholds are heuristic and deliberately
/// conservative (only the most egregious outliers surface) so the LLM gets a short, actionable list.
struct SmellFinding: Codable, Sendable {
    var smell: String
    var type: String
    var module: String
    var location: String?
    var detail: String
    var severity: String
}

func detectSmells(metrics: CodeMetrics, artifact: CodeArtifact) -> [SmellFinding] {
    var findings: [SmellFinding] = []
    let flat = flattenTypes(artifact.types)
    let typeByID: [String: TypeDeclaration] = Dictionary(flat.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    for typeMetric in metrics.types {
        let loc = typeByID[typeMetric.id]?.location.map { "\($0.filePath):\($0.line)" }

        // God class: high WMC + high fan-out
        if typeMetric.weightedMethods >= 20 && typeMetric.fanOut >= 10 {
            findings.append(SmellFinding(
                smell: "god_class",
                type: typeMetric.name,
                module: typeMetric.module,
                location: loc,
                detail: "WMC=\(typeMetric.weightedMethods), fan-out=\(typeMetric.fanOut)",
                severity: "high"))
        }

        // Shotgun surgery candidate: very high fan-in (many types depend on this one)
        if typeMetric.fanIn >= 15 {
            findings.append(SmellFinding(
                smell: "shotgun_surgery",
                type: typeMetric.name,
                module: typeMetric.module,
                location: loc,
                detail: "fan-in=\(typeMetric.fanIn) — changes here ripple to many dependents",
                severity: typeMetric.fanIn >= 25 ? "high" : "medium"))
        }

        // Feature envy: high fan-out but few methods (talks to everyone, does little itself)
        if typeMetric.fanOut >= 10 && typeMetric.weightedMethods <= 3 {
            findings.append(SmellFinding(
                smell: "feature_envy",
                type: typeMetric.name,
                module: typeMetric.module,
                location: loc,
                detail: "fan-out=\(typeMetric.fanOut), WMC=\(typeMetric.weightedMethods)",
                severity: "medium"))
        }
    }

    // Unstable abstractions: modules far from the main sequence
    for module in metrics.modules where module.distanceFromMainSequence > 0.7 && module.typeCount >= 3 {
        findings.append(SmellFinding(
            smell: "unstable_abstraction",
            type: module.name,
            module: module.name,
            location: nil,
            detail: "D=\(String(format: "%.2f", module.distanceFromMainSequence)), "
                + "I=\(String(format: "%.2f", module.instability)), "
                + "A=\(String(format: "%.2f", module.abstractness))",
            severity: module.distanceFromMainSequence > 0.85 ? "high" : "medium"))
    }

    return findings
}

/// Flattens nested type hierarchies into a single list.
func flattenTypes(_ types: [TypeDeclaration]) -> [TypeDeclaration] {
    var result: [TypeDeclaration] = []
    for type in types {
        var copy = type
        let nested = flattenTypes(type.nestedTypes)
        copy.nestedTypes = []
        result.append(copy)
        result.append(contentsOf: nested)
    }
    return result
}
