import SwiftUI
import UMLConformance
import UMLCore

/// Section view for a codebase's analyses (currently the architecture-conformance check). An analysis
/// produces a report, not a canvas, so it lives here rather than among the diagrams. Shows the check's
/// status and its violations inline, and opens the rules editor.
struct CodebaseAnalysesSection: View {
    let codebase: Codebase
    let artifact: CodeArtifact

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var editing = false

    private var configuration: ArchitectureCheckConfiguration? {
        guard let config = codebase.architectureCheck, !config.rulesPath.isEmpty else { return nil }
        return config
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Analyses")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 12)

            architectureCard
                .padding(.horizontal)

            analysisCard(icon: "nose", tint: .orange, title: "Code Smells") {
                SmellsReportView(artifact: artifact)
            }
            .padding(.horizontal)

            analysisCard(icon: "trash", tint: .orange, title: "Dead Code") {
                DeadCodeReportView(artifact: artifact)
            }
            .padding(.horizontal)

            analysisCard(icon: "stethoscope", tint: .blue, title: "Parse Health") {
                HealthReportView(artifact: artifact)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $editing) {
            ArchitectureCheckEditorSheet(codebaseID: codebase.id, artifact: artifact)
                .environmentObject(model)
        }
    }

    private var architectureCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.shield").font(.title2).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Architecture Check").font(.headline)
                    Text(statusLine).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button(configuration == nil ? "Set Up…" : "Edit…") { editing = true }
            }
            if configuration != nil {
                Divider()
                report
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Chrome for a computed analysis card (no configuration): an icon + title header, a divider, then
    /// the analysis's own report view.
    private func analysisCard(
        icon: String, tint: Color, title: String, @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title2).foregroundStyle(tint)
                Text(title).font(.headline)
                Spacer()
            }
            Divider()
            content()
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
