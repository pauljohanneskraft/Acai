import UMLCore
import UMLDiff

extension ArtifactDiff {
    /// A human-sized changelog of the architectural delta — the precise, reviewable summary that a
    /// redrawn diagram cannot give. Groups added/removed types, edge changes phrased in prose
    /// ("`A` now depends on `B`", "`X`→`Y` inheritance removed") and notable metric movement.
    func humanReport() -> String {
        if isEmpty { return "No structural changes." }

        var sections: [String] = []

        if !addedTypes.isEmpty {
            sections.append(section("Added types", addedTypes.map { "+ \($0)" }))
        }
        if !removedTypes.isEmpty {
            sections.append(section("Removed types", removedTypes.map { "- \($0)" }))
        }
        if !changedTypes.isEmpty {
            sections.append(section("Changed types", changedTypes.map(Self.line(for:))))
        }

        var edgeLines: [String] = []
        edgeLines += addedRelationships.map { "+ " + Self.phrase($0) }
        edgeLines += removedRelationships.map { "- " + Self.phrase($0, removed: true) }
        edgeLines += changedRelationships.map { "~ " + Self.phrase($0.after) + " (multiplicity/label changed)" }
        if !edgeLines.isEmpty {
            sections.append(section("Relationship changes", edgeLines))
        }

        let metricLines = moduleMetricDeltas.compactMap(Self.line(for:))
        if !metricLines.isEmpty {
            sections.append(section("Module metric changes", metricLines))
        }

        return sections.joined(separator: "\n\n") + "\n"
    }

    private func section(_ title: String, _ lines: [String]) -> String {
        ([title + ":"] + lines.map { "  " + $0 }).joined(separator: "\n")
    }

    private static func line(for change: TypeChange) -> String {
        var parts: [String] = []
        if let kind = change.kindChange {
            parts.append("\(kind.before.rawValue) → \(kind.after.rawValue)")
        }
        if let access = change.accessChange {
            parts.append("access \(access.before?.rawValue ?? "default") → \(access.after?.rawValue ?? "default")")
        }
        if !change.addedMembers.isEmpty { parts.append("+\(change.addedMembers.count) member(s)") }
        if !change.removedMembers.isEmpty { parts.append("-\(change.removedMembers.count) member(s)") }
        return "~ \(change.id): \(parts.joined(separator: ", "))"
    }

    private static func line(for delta: ModuleMetricDelta) -> String? {
        var parts: [String] = []
        if let d = delta.distanceFromMainSequence { parts.append("distance \(fmt(d.before)) → \(fmt(d.after))") }
        if let i = delta.instability { parts.append("instability \(fmt(i.before)) → \(fmt(i.after))") }
        if let a = delta.abstractness { parts.append("abstractness \(fmt(a.before)) → \(fmt(a.after))") }
        guard !parts.isEmpty else { return nil }
        return "\(delta.module): \(parts.joined(separator: ", "))"
    }

    /// Phrases a relationship as a sentence. `removed` flips the tense so a dropped edge reads
    /// naturally ("`X`→`Y` inheritance removed").
    private static func phrase(_ rel: Relationship, removed: Bool = false) -> String {
        let source = short(rel.source)
        let target = short(rel.target)
        if removed {
            switch rel.kind {
            case .inheritance:
                return "\(source)→\(target) inheritance removed"
            case .conformance:
                return "\(source) no longer conforms to \(target)"
            default:
                return "\(source) no longer depends on \(target) (\(rel.kind.rawValue))"
            }
        }
        switch rel.kind {
        case .inheritance:
            return "\(source) now inherits from \(target)"
        case .conformance:
            return "\(source) now conforms to \(target)"
        case .composition, .aggregation:
            return "\(source) now owns \(target) (\(rel.kind.rawValue))"
        default:
            return "\(source) now depends on \(target) (\(rel.kind.rawValue))"
        }
    }

    private static func short(_ id: String) -> String { id.components(separatedBy: ".").last ?? id }
    private static func fmt(_ value: Double) -> String { String(format: "%.2f", value) }
}
