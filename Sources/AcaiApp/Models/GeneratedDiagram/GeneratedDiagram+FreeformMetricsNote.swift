import AcaiDiagram
import Foundation

/// B22: text for the read-only `.note` node `PackageFreeformConversion`/`CallGraphFreeformConversion`
/// (`PackageFreeformConversion.swift`/`CallGraphFreeformConversion.swift`) append when the user
/// opts in to carrying over the coupling/coverage figures that conversion would otherwise silently
/// drop.

extension PackageDiagram {
    /// One line per module summarizing its coupling metrics — the text carried into the `.note`
    /// node `PackageFreeformConversion` appends when `includeMetricsNote` is set.
    var metricsNoteText: String {
        nodes.map { module in
            "\(module.name): Ca=\(module.afferentCoupling) Ce=\(module.efferentCoupling) "
                + "I=\(String(format: "%.2f", module.instability)) "
                + "A=\(String(format: "%.2f", module.abstractness)) "
                + "D=\(String(format: "%.2f", module.distanceFromMainSequence))"
        }.joined(separator: "\n")
    }
}

extension CallGraph.Coverage {
    /// The resolved/total call-site summary — the text carried into the `.note` node
    /// `CallGraphFreeformConversion` appends when `includeMetricsNote` is set.
    var metricsNoteText: String {
        "Resolved \(resolved) / \(total) call sites (\(Int((fraction * 100).rounded()))%)"
    }
}
