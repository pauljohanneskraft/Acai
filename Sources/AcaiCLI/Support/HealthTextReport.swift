import AcaiCore

/// The human-readable form of ``HealthCheck/Report``: the trust score, the scope the parse ran over
/// (which project roots were found and by what), and every diagnostic.
///
/// The roots are what make "this folder analysed to fewer types than it contains" diagnosable, so
/// they are printed whether or not anything went wrong — a clean score over the wrong scope is the
/// case worth catching.
struct HealthTextReport {
    let report: HealthCheck.Report

    func render() -> String {
        (scoreLines + rootLines + diagnosticLines).joined(separator: "\n") + "\n"
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
            return ["Project roots: none recorded (analysis predates root discovery, or none was run)"]
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
