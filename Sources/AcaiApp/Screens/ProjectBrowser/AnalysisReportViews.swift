import SwiftUI
import AcaiQuality
import AcaiCore
import AcaiDiagram
import AcaiLibrary

/// A single finding row — a rule-kind capsule, subject, message and a selectable `file:line`. Shared
/// by the quality-check report views so every finding renders identically. Clickable to reveal its
/// file in Finder when `codebase` is supplied.
struct ViolationRowView: View {
    let violation: Violation
    var tint: Color = .red
    var codebase: Codebase?

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
        .revealsInFinder(codebase: codebase, relativePath: violation.source?.filePath)
    }
}

/// A `file:line` row shared by the dead-code and health reports. Clickable to reveal its file in
/// Finder when `codebase` is supplied.
private struct LocationRow: View {
    let title: String
    let detail: String?
    let location: SourceLocation?
    var codebase: Codebase?

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
        .revealsInFinder(codebase: codebase, relativePath: location?.filePath)
    }
}

/// The card body cap: report cards show the top findings inline, not an unbounded wall.
let analysisReportLimit = 20

/// Dead-code candidates with the call-graph coverage floor. The report is computed by the enclosing
/// section (which also surfaces the counts in its header) and injected, so the scan runs once. Rows
/// reveal their file in Finder when `codebase` is supplied.
struct DeadCodeReportView: View {
    let report: DeadCodeScan.Report
    var codebase: Codebase?

    var body: some View {
        let coverage = Int((report.coverage.fraction * 100).rounded())
        if report.candidates.isEmpty {
            QualityCheckPlaceholder(
                text: "No dead-code candidates (call-graph coverage \(coverage)%).",
                systemImage: "checkmark.seal")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Candidates below this coverage floor may be false positives.")
                    .font(.caption).foregroundStyle(.secondary)
                let candidates = Array(report.candidates.prefix(analysisReportLimit).enumerated())
                ForEach(candidates, id: \.offset) { _, candidate in
                    LocationRow(
                        title: candidate.id, detail: nil, location: candidate.location, codebase: codebase)
                }
            }
        }
    }
}

/// Parse-health score and diagnostics. The report is computed by the enclosing section (which also
/// surfaces the score in its header) and injected, so the check runs once. Rows reveal their file in
/// Finder when `codebase` is supplied.
struct HealthReportView: View {
    let report: HealthCheck.Report
    var codebase: Codebase?

    var body: some View {
        let percent = Int((report.score * 100).rounded())
        if report.diagnostics.isEmpty {
            QualityCheckPlaceholder(
                text: "Parse health \(percent)% — no diagnostics across \(report.typeCount) type(s).",
                systemImage: "checkmark.seal")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                let diagnostics = Array(report.diagnostics.prefix(analysisReportLimit).enumerated())
                ForEach(diagnostics, id: \.offset) { _, diagnostic in
                    LocationRow(
                        title: diagnostic.message, detail: diagnostic.kind.rawValue,
                        location: diagnostic.location, codebase: codebase)
                }
            }
        }
    }
}
