import SwiftUI
import UMLConformance
import UMLCore
import UMLDiagram
import UMLLibrary

/// A single finding row — a rule-kind capsule, subject, message and a selectable `file:line`. Shared
/// by the architecture-check report and the code-smell report so both render findings identically.
struct ViolationRowView: View {
    let violation: Violation
    var tint: Color = .red

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(violation.ruleKind)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(tint.opacity(0.12))
                    .clipShape(Capsule())
                Text(violation.subject).font(.callout.bold())
            }
            Text(violation.message).font(.callout)
            if let source = violation.source {
                Text("\(source.filePath):\(source.line)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// A `file:line` row shared by the dead-code and health reports.
private struct LocationRow: View {
    let title: String
    let detail: String?
    let location: SourceLocation?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.callout)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            if let location {
                Text("\(location.filePath):\(location.line)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// The card body cap: report cards show the top findings inline, not an unbounded wall.
private let analysisReportLimit = 20

/// Ranked code smells for the codebase (top findings inline).
struct SmellsReportView: View {
    let artifact: CodeArtifact

    private var findings: [Violation] {
        SmellScan(
            artifact: artifact,
            annotationStereotypes: artifact.standardLanguageConfiguration.annotationStereotypes
        ).findings
    }

    var body: some View {
        let findings = findings
        if findings.isEmpty {
            ArchitectureCheckPlaceholder(text: "No smells found.", systemImage: "checkmark.seal")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(findings.count) smell(s)")
                    .font(.subheadline.bold()).foregroundStyle(.orange)
                ForEach(Array(findings.prefix(analysisReportLimit).enumerated()), id: \.offset) { _, finding in
                    ViolationRowView(violation: finding, tint: .orange)
                }
            }
        }
    }
}

/// Dead-code candidates with the call-graph coverage floor.
struct DeadCodeReportView: View {
    let artifact: CodeArtifact

    private var report: DeadCodeScan.Report {
        DeadCodeScan(
            artifact: artifact,
            entryPoints: artifact.standardLanguageConfiguration.entryPointMarkers
        ).report
    }

    var body: some View {
        let report = report
        let coverage = Int((report.coverage.fraction * 100).rounded())
        if report.candidates.isEmpty {
            ArchitectureCheckPlaceholder(
                text: "No dead-code candidates (call-graph coverage \(coverage)%).",
                systemImage: "checkmark.seal")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(report.candidates.count) candidate(s) · call-graph coverage \(coverage)%")
                    .font(.subheadline.bold()).foregroundStyle(.orange)
                Text("Candidates below this coverage floor may be false positives.")
                    .font(.caption).foregroundStyle(.secondary)
                let candidates = Array(report.candidates.prefix(analysisReportLimit).enumerated())
                ForEach(candidates, id: \.offset) { _, candidate in
                    LocationRow(title: candidate.id, detail: nil, location: candidate.location)
                }
            }
        }
    }
}

/// Parse-health score and diagnostics.
struct HealthReportView: View {
    let artifact: CodeArtifact

    private var report: HealthCheck.Report { HealthCheck(artifact: artifact).report }

    var body: some View {
        let report = report
        let percent = Int((report.score * 100).rounded())
        if report.diagnostics.isEmpty {
            ArchitectureCheckPlaceholder(
                text: "Parse health \(percent)% — no diagnostics across \(report.typeCount) type(s).",
                systemImage: "checkmark.seal")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Parse health \(percent)% · \(report.diagnosticCount) diagnostic(s)")
                    .font(.subheadline.bold())
                    .foregroundStyle(percent >= 90 ? Color.primary : Color.red)
                let diagnostics = Array(report.diagnostics.prefix(analysisReportLimit).enumerated())
                ForEach(diagnostics, id: \.offset) { _, diagnostic in
                    LocationRow(
                        title: diagnostic.message, detail: diagnostic.kind.rawValue, location: diagnostic.location)
                }
            }
        }
    }
}
