import AcaiCore

/// Prints the roots even on a clean score: a clean score over the wrong scope is the case worth catching.
struct HealthTextReport {
    let report: HealthCheck.Report

    func render() -> String {
        let diagnostics = diagnosticLines
        let separator = diagnostics.isEmpty ? [] : [""]
        return (scoreLines + rootLines + separator + diagnostics).joined(separator: "\n") + "\n"
    }

    private var scoreLines: [String] {
        let percent = Int((report.score * 100).rounded())
        return [
            "Parse health: \(percent)% "
            + "(\(report.diagnosticCount) diagnostic(s) across \(report.typeCount) type(s))"
        ]
    }

    private var rootLines: [String] {
        guard !report.discoveredRoots.isEmpty else {
            return ["Project roots: none recorded"]
        }
        var lines = ["Project roots (\(report.discoveredRoots.count)):"]
        for root in report.discoveredRoots {
            let languages = root.languages.map(\.rawValue).joined(separator: ", ")
            lines.append("  \(root.path) — \(root.detector) [\(languages)]")
            let sources = root.sourceDirs.isEmpty ? "(none)" : root.sourceDirs.joined(separator: ", ")
            lines.append("    sources: \(sources)")
        }
        if report.isFallbackOnly {
            lines.append("  No build system recognised; analysed by file extension.")
        }
        return lines
    }

    private var diagnosticLines: [String] {
        report.diagnostics.map {
            "  \($0.location.jumpTarget): \($0.kind.rawValue): \($0.message)"
        }
    }
}
