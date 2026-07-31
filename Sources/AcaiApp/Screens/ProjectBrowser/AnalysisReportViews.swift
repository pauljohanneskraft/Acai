import SwiftUI
import AcaiQuality
import AcaiCore
import AcaiDiagram
import AcaiLibrary

/// A single finding row — a rule-kind capsule, subject, message and a selectable `file:line`. Shared
/// by the quality-check report views so every finding renders identically. Offers the full "Open
/// in…" resolution (default tap-through + context menu, with Finder reveal kept as an additional
/// macOS-only secondary action) when `artifact`/`codebase` are supplied; also offers a "View Source"
/// (Quick Look) action when both `codebase` and a source location are available.
struct ViolationRowView: View {
    let violation: Violation
    var tint: Color = .red
    var codebase: Codebase?
    /// Needed to resolve `violation.subject` into a `CodeElementReference` — `nil` in the rules
    /// editor's live preview, which has no codebase context to resolve a diagram against either, so
    /// "Open in…" is unavailable there just like Finder reveal already was.
    var artifact: CodeArtifact?
    /// The Cycle Diagram entry point for a `cycle`-kind violation: shown only when non-`nil` *and*
    /// `violation.ruleKind == "cycle"`. A plain closure rather than an `@EnvironmentObject`
    /// dependency on `ProjectBrowserViewModel` — this row is also rendered by the quality rules
    /// editor's live preview, which has no project/codebase context to create a diagram in, so a
    /// missing environment object there would be a hard crash rather than a degraded row. The one
    /// call site that has both a `model` and a `codebase` builds this closure; everywhere else
    /// passes `nil`.
    var onViewAsDiagram: (() -> Void)?

    private var reference: CodeElementReference? {
        artifact.flatMap { violation.codeElementReference(in: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // `openInCodeElement` wraps its content in a `Button` — kept scoped to just this block
            // (not the whole row) so the buttons below are sibling controls, not nested inside
            // another button, which SwiftUI doesn't reliably route taps through.
            findingSummary
                .openInCodeElement(reference, codebase: codebase, relativePath: violation.source?.filePath)
            HStack(spacing: 8) {
                if let codebase, let source = violation.source {
                    ViewSourceButton(codebase: codebase, relativePath: source.filePath)
                }
                if violation.ruleKind == "cycle", let onViewAsDiagram {
                    Button(action: onViewAsDiagram) {
                        Label("View as Diagram", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityIdentifier("violation.viewAsDiagramButton")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var findingSummary: some View {
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
    }
}

/// A `file:line` row shared by the dead-code and health reports. Offers the full "Open in…"
/// resolution when `reference`/`codebase` are supplied (Finder reveal kept as an additional
/// macOS-only secondary action), plus a "View Source" (Quick Look) action whenever `codebase` and
/// `location` are both available — including a health-check diagnostic, which carries no resolvable
/// `reference` at all (a line-level parse issue isn't a type/method/module), so View Source is its
/// only action there.
private struct LocationRow: View {
    let title: String
    let detail: String?
    let location: SourceLocation?
    var codebase: Codebase?
    var reference: CodeElementReference?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            summary
                .openInCodeElement(reference, codebase: codebase, relativePath: location?.filePath)
            if let codebase, let location {
                ViewSourceButton(codebase: codebase, relativePath: location.filePath)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var summary: some View {
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
    }
}

/// The card body cap: report cards show the top findings inline, not an unbounded wall.
let analysisReportLimit = 20

/// Dead-code candidates with the call-graph coverage floor. The report is computed by the enclosing
/// section (which also surfaces the counts in its header) and injected, so the scan runs once. Rows
/// get the full "Open in…" resolution when `artifact`/`codebase` are supplied.
struct DeadCodeReportView: View {
    let report: DeadCodeScan.Report
    /// Needed to resolve a candidate's `"TypeName.methodName"` id into a `CodeElementReference`.
    var artifact: CodeArtifact?
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
                        title: candidate.id, detail: nil, location: candidate.location, codebase: codebase,
                        reference: artifact.flatMap { candidate.codeElementReference(in: $0) })
                }
            }
        }
    }
}

/// Parse-health score and diagnostics. The report is computed by the enclosing section (which also
/// surfaces the score in its header) and injected, so the check runs once. A `ParseDiagnostic`
/// carries no type/method identity, so rows get only the "View Source" action (via `LocationRow`) —
/// there's nothing for "Open in…" to resolve.
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
