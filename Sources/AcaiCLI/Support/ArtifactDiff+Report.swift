import AcaiCore
import AcaiDiff

extension ArtifactDiff {
    /// A human-sized changelog of the architectural delta — the precise, reviewable summary that a
    /// redrawn diagram cannot give. Groups added/removed types, edge changes phrased in prose
    /// ("`A` now depends on `B`", "`X`→`Y` inheritance removed") and notable metric movement.
    func humanReport() -> String {
        if isEmpty { return "No structural changes." }

        var sections: [String] = []

        if !addedTypes.isEmpty {
            sections.append(ReportSection(title: "Added types", lines: addedTypes.map { "+ \($0)" }).text)
        }
        if !removedTypes.isEmpty {
            sections.append(ReportSection(title: "Removed types", lines: removedTypes.map { "- \($0)" }).text)
        }
        if !changedTypes.isEmpty {
            sections.append(ReportSection(title: "Changed types", lines: changedTypes.map(\.reportLine)).text)
        }

        var edgeLines: [String] = []
        edgeLines += addedRelationships.map { "+ " + $0.reportPhrase() }
        edgeLines += removedRelationships.map { "- " + $0.reportPhrase(removed: true) }
        edgeLines += changedRelationships.map { "~ " + $0.after.reportPhrase() + " (multiplicity/label changed)" }
        if !edgeLines.isEmpty {
            sections.append(ReportSection(title: "Relationship changes", lines: edgeLines).text)
        }

        let metricLines = moduleMetricDeltas.compactMap(\.reportLine)
        if !metricLines.isEmpty {
            sections.append(ReportSection(title: "Module metric changes", lines: metricLines).text)
        }

        let typeMetricLines = typeMetricDeltas.compactMap(\.reportLine)
        if !typeMetricLines.isEmpty {
            sections.append(ReportSection(title: "Type metric changes", lines: typeMetricLines).text)
        }

        return sections.joined(separator: "\n\n") + "\n"
    }
}

/// One titled, indented block of a `humanReport()`. A value (title + lines) that renders itself,
/// rather than a free formatting function.
private struct ReportSection {
    let title: String
    let lines: [String]

    var text: String {
        ([title + ":"] + lines.map { "  " + $0 }).joined(separator: "\n")
    }
}

private extension TypeChange {
    /// One `~ Id: …` line summarising a type's kind/access/member changes.
    var reportLine: String {
        var parts: [String] = []
        if let kind = kindChange {
            parts.append("\(kind.before.rawValue) → \(kind.after.rawValue)")
        }
        if let access = accessChange {
            parts.append("access \(access.before.rawValue) → \(access.after.rawValue)")
        }
        if !addedMembers.isEmpty { parts.append("+\(addedMembers.count) member(s)") }
        if !removedMembers.isEmpty { parts.append("-\(removedMembers.count) member(s)") }
        return "~ \(id): \(parts.joined(separator: ", "))"
    }
}

private extension ModuleMetricDelta {
    /// A `module: …` line of changed package metrics, or `nil` when nothing moved.
    var reportLine: String? {
        var parts: [String] = []
        if let d = distanceFromMainSequence { parts.append("distance \(d.twoDecimalArrow)") }
        if let i = instability { parts.append("instability \(i.twoDecimalArrow)") }
        if let a = abstractness { parts.append("abstractness \(a.twoDecimalArrow)") }
        guard !parts.isEmpty else { return nil }
        return "\(module): \(parts.joined(separator: ", "))"
    }
}

private extension TypeMetricDelta {
    /// An `id: …` line of changed type metrics, or `nil` when nothing moved.
    var reportLine: String? {
        var parts: [String] = []
        if let f = fanIn { parts.append("fan-in \(f.before) → \(f.after)") }
        if let f = fanOut { parts.append("fan-out \(f.before) → \(f.after)") }
        if let d = depthOfInheritance { parts.append("DIT \(d.before) → \(d.after)") }
        guard !parts.isEmpty else { return nil }
        return "\(id): \(parts.joined(separator: ", "))"
    }
}

private extension Relationship {
    /// Phrases this relationship as a sentence. `removed` flips the tense so a dropped edge reads
    /// naturally ("`X`→`Y` inheritance removed").
    func reportPhrase(removed: Bool = false) -> String {
        let source = self.source.lastDottedComponent
        let target = self.target.lastDottedComponent
        if removed {
            switch kind {
            case .inheritance:
                return "\(source)→\(target) inheritance removed"
            case .conformance:
                return "\(source) no longer conforms to \(target)"
            default:
                return "\(source) no longer depends on \(target) (\(kind.rawValue))"
            }
        }
        switch kind {
        case .inheritance:
            return "\(source) now inherits from \(target)"
        case .conformance:
            return "\(source) now conforms to \(target)"
        case .composition, .aggregation:
            return "\(source) now owns \(target) (\(kind.rawValue))"
        default:
            return "\(source) now depends on \(target) (\(kind.rawValue))"
        }
    }
}

private extension String {
    /// The last `.`-separated component (a qualified id's simple name), or the whole string.
    var lastDottedComponent: String { components(separatedBy: ".").last ?? self }
}

private extension Double {
    /// This value formatted to two decimal places.
    var twoDecimals: String { String(format: "%.2f", self) }
}

private extension Change where T == Double {
    /// `before → after`, each to two decimals — the shared spelling for package-metric movement.
    var twoDecimalArrow: String { "\(before.twoDecimals) → \(after.twoDecimals)" }
}
