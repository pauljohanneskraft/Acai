import SwiftUI
import UMLConformance
import UMLCore

/// The architecture-conformance check as its own collapsible section. An analysis produces a report,
/// not a canvas, so it lives here rather than among the diagrams. Shows the check's status and its
/// violations inline, and opens the rules editor from the header.
struct ArchitectureCheckSection: View {
    let codebase: Codebase
    let artifact: CodeArtifact

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var editing = false

    private var configuration: ArchitectureCheckConfiguration? {
        guard let config = codebase.architectureCheck, !config.rulesPath.isEmpty else { return nil }
        return config
    }

    var body: some View {
        CollapsibleSection(title: "Architecture Check") {
            Button(configuration == nil ? "Set Up…" : "Edit…") { editing = true }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Text(statusLine)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                if configuration != nil {
                    report
                }
            }
            .padding(.horizontal)
        }
        .sheet(isPresented: $editing) {
            ArchitectureCheckEditorSheet(codebaseID: codebase.id, artifact: artifact)
                .environmentObject(model)
        }
    }

    @ViewBuilder
    private var report: some View {
        switch resolvedRules {
        case .none:
            EmptyView()
        case .success(let rules):
            ArchitectureCheckReportView(rules: rules, artifact: artifact)
        case .failure(let error):
            ArchitectureCheckPlaceholder(
                text: "Could not load rules: \(error.localizedDescription)",
                systemImage: "exclamationmark.triangle")
        }
    }

    /// `nil` when no check is configured, otherwise the decoded rules or the load error.
    private var resolvedRules: Result<ConformanceRules, Error>? {
        configuration.map { config in Result { try config.loadRules() } }
    }

    private var statusLine: String {
        guard let config = configuration else { return "No check configured yet." }
        let origin = model.store.isManaged(path: config.rulesPath)
            ? "Defined in app"
            : (config.rulesPath as NSString).abbreviatingWithTildeInPath
        switch resolvedRules {
        case .success(let rules):
            return "\(origin) · \(rules.ruleCount) rule(s)"
        default:
            return origin
        }
    }
}

/// Ranked code smells as their own collapsible section.
struct CodeSmellsSection: View {
    let artifact: CodeArtifact

    var body: some View {
        CollapsibleSection(title: "Code Smells") {
            SmellsReportView(artifact: artifact)
                .padding(.horizontal)
        }
    }
}

/// Dead-code candidates as their own collapsible section.
struct DeadCodeSection: View {
    let artifact: CodeArtifact

    var body: some View {
        CollapsibleSection(title: "Dead Code") {
            DeadCodeReportView(artifact: artifact)
                .padding(.horizontal)
        }
    }
}

/// Parse health as its own collapsible section. Kept unobtrusive on a clean codebase: collapsed by
/// default with a compact score in the header, expanding only when there are diagnostics.
struct ParseHealthSection: View {
    let artifact: CodeArtifact

    private var report: HealthCheck.Report { HealthCheck(artifact: artifact).report }

    var body: some View {
        let report = report
        let percent = Int((report.score * 100).rounded())
        CollapsibleSection(
            title: "Parse Health",
            defaultExpanded: !report.diagnostics.isEmpty
        ) {
            Text("health \(percent)%")
                .font(.caption)
                .foregroundStyle(percent >= 90 ? Color.secondary : Color.red)
        } content: {
            HealthReportView(artifact: artifact)
                .padding(.horizontal)
        }
    }
}
