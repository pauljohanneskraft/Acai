import SwiftUI
import AcaiQuality
import AcaiCore
import AcaiDiagram
import AcaiLibrary

/// Shared by the quality-check report views so every finding renders identically.
struct ViolationRowView: View {
    let violation: Violation
    var tint: Color = .red
    var codebase: Codebase?
    /// `nil` in the rules editor's live preview, which has no codebase context to resolve a
    /// reference against.
    var artifact: CodeArtifact?
    /// A plain closure rather than an `@EnvironmentObject` dependency on `ProjectBrowserViewModel` —
    /// this row is also rendered by the quality rules editor's live preview, which has no
    /// project/codebase context to create a diagram in, so a missing environment object there would
    /// be a hard crash rather than a degraded row.
    var onViewAsDiagram: (() -> Void)?

    private var reference: CodeElementReference? {
        artifact.flatMap { violation.codeElementReference(in: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingXS) {
            // `openInCodeElement` wraps its content in a `Button` — kept scoped to just this block
            // (not the whole row) so the buttons below are sibling controls, not nested inside
            // another button, which SwiftUI doesn't reliably route taps through.
            findingSummary
                .openInCodeElement(reference, codebase: codebase, relativePath: violation.source?.filePath)
            HStack(spacing: .spacingS) {
                if let codebase, let source = violation.source {
                    ViewSourceButton(codebase: codebase, relativePath: source.filePath)
                }
                if violation.ruleKind == "cycle", let onViewAsDiagram {
                    Button(action: onViewAsDiagram) {
                        Label(.app("View.ViolationRowView.ViewDiagram"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityIdentifier("violation.viewAsDiagramButton")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.spacingS)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var findingSummary: some View {
        VStack(alignment: .leading, spacing: .spacingXS) {
            HStack(spacing: .spacingS) {
                Text(verbatim: violation.ruleKind)
                    .font(.caption.monospaced())
                    .padding(.horizontal, .spacingXS).padding(.vertical, .spacingXXS)
                    .background(tint.opacity(0.12))
                    .clipShape(Capsule())
                Text(verbatim: violation.subject).font(.callout.bold())
            }
            Text(verbatim: violation.message).font(.callout)
            if let source = violation.source {
                Text(verbatim: "\(source.filePath):\(source.line)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shared by the dead-code and health reports. A health-check diagnostic carries no resolvable
/// `reference` (a line-level parse issue isn't a type/method/module), so View Source is its only
/// action.
private struct LocationRow: View {
    let title: String
    let detail: String?
    let location: SourceLocation?
    var codebase: Codebase?
    var reference: CodeElementReference?

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingXS) {
            summary
                .openInCodeElement(reference, codebase: codebase, relativePath: location?.filePath)
            if let codebase, let location {
                ViewSourceButton(codebase: codebase, relativePath: location.filePath)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.spacingS)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: .spacingXXS) {
            Text(verbatim: title).font(.callout)
            if let detail {
                Text(verbatim: detail).font(.caption).foregroundStyle(.secondary)
            }
            if let location {
                Text(verbatim: "\(location.filePath):\(location.line)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

let analysisReportLimit = 20

struct DeadCodeReportView: View {
    let report: DeadCodeScan.Report
    /// Needed to resolve a candidate's `"TypeName.methodName"` id into a `CodeElementReference`.
    var artifact: CodeArtifact?
    var codebase: Codebase?

    var body: some View {
        let coverage = Int((report.coverage.fraction * 100).rounded())
        if report.candidates.isEmpty {
            QualityCheckPlaceholder(
                text: .app("View.DeadCodeSection.NoCandidates \(coverage)"),
                systemImage: "checkmark.seal")
        } else {
            VStack(alignment: .leading, spacing: .spacingS) {
                Text(.app("View.DeadCodeReportView.CandidatesBelowCoverageFloor"))
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

/// A `ParseDiagnostic` carries no type/method identity, so rows get only the "View Source" action
/// (via `LocationRow`) — there's nothing for "Open in…" to resolve.
///
/// The discovered roots are shown above the diagnostics whether or not anything went wrong: a clean
/// score over the wrong scope is exactly the case a type count alone cannot explain.
struct HealthReportView: View {
    let report: HealthCheck.Report
    var codebase: Codebase?

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingM) {
            if !report.discoveredRoots.isEmpty {
                DiscoveredRootsView(roots: report.discoveredRoots, isFallbackOnly: report.isFallbackOnly)
            }
            diagnostics
        }
    }

    @ViewBuilder private var diagnostics: some View {
        let percent = Int((report.score * 100).rounded())
        if report.diagnostics.isEmpty {
            let types = String(localized: .app("View.ParseHealthSection.Types \(report.typeCount)"))
            QualityCheckPlaceholder(
                text: .app("View.ParseHealthSection.NoDiagnostics \(percent) \(types)"),
                systemImage: "checkmark.seal")
        } else {
            VStack(alignment: .leading, spacing: .spacingS) {
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

/// Which project roots discovery claimed, and by which detector — the scope the parse ran over.
///
/// Paths, detector names and language identifiers are all parser output, so they are `verbatim`
/// throughout; only the labels around them are localized.
struct DiscoveredRootsView: View {
    let roots: [CodeArtifact.DiscoveredRoot]
    let isFallbackOnly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingS) {
            Text(.app("View.DiscoveredRootsView.ProjectRoots \(roots.count)"))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(roots.prefix(analysisReportLimit).enumerated()), id: \.offset) { _, root in
                row(for: root)
            }
            if isFallbackOnly {
                Label {
                    Text(.app("View.DiscoveredRootsView.NoBuildSystemRecognised"))
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("healthReport.noBuildSystemRecognised")
            }
        }
        .accessibilityIdentifier("healthReport.discoveredRoots")
    }

    private func row(for root: CodeArtifact.DiscoveredRoot) -> some View {
        let languages = root.languages.map(\.rawValue).joined(separator: ", ")
        let sources = root.sourceDirs.joined(separator: ", ")
        return VStack(alignment: .leading, spacing: .spacingXXS) {
            Text(verbatim: root.path).font(.callout.monospaced())
            Text(verbatim: "\(root.detector) · \(languages)")
                .font(.caption).foregroundStyle(.secondary)
            if !sources.isEmpty {
                Text(.app("View.DiscoveredRootsView.Sources \(sources)"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
