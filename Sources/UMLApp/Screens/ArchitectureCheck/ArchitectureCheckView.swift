import AppKit
import SwiftUI
import UMLConformance
import UMLCore
import UMLLibrary
import UniformTypeIdentifiers
import Yams

/// Runs an architecture-conformance check against the codebase artifact and lists the violations.
/// Not a canvas: the user picks a YAML rules file, and the report is recomputed from the artifact
/// each render (the only persisted state is the rules-file path).
struct ArchitectureCheckView: View {
    let diagram: GeneratedDiagram
    let artifact: CodeArtifact
    let codebase: Codebase

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var rulesPath: String

    init(diagram: GeneratedDiagram, artifact: CodeArtifact, codebase: Codebase) {
        self.diagram = diagram
        self.artifact = artifact
        self.codebase = codebase
        _rulesPath = State(initialValue: diagram.architectureCheckConfiguration?.rulesPath ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.title2)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Architecture Check").font(.title3.bold())
                Text(rulesPath.isEmpty ? "No rules file selected"
                     : (rulesPath as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                chooseRulesFile()
            } label: {
                Label(rulesPath.isEmpty ? "Choose Rules File…" : "Change…", systemImage: "doc.badge.gearshape")
            }
        }
        .padding()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if rulesPath.isEmpty {
            placeholder("Choose a YAML rules file to validate this codebase against.")
        } else {
            switch evaluation {
            case .failure(let error):
                placeholder(
                    "Could not load rules: \(error.localizedDescription)",
                    systemImage: "exclamationmark.triangle")
            case .success(let report) where report.isPassing:
                placeholder(
                    "Conformance OK — \(report.checkedRuleCount) rule(s) checked, no violations.",
                    systemImage: "checkmark.seal")
            case .success(let report):
                violationList(report)
            }
        }
    }

    private func violationList(_ report: ConformanceReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(report.violations.count) violation(s) across \(report.checkedRuleCount) rule(s)")
                .font(.headline)
                .padding(.horizontal)
                .padding(.vertical, 8)
            List(Array(report.violations.enumerated()), id: \.offset) { _, violation in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(violation.ruleKind)
                            .font(.caption.monospaced())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red.opacity(0.12))
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
                .padding(.vertical, 4)
            }
        }
    }

    private func placeholder(_ text: String, systemImage: String = "doc.text.magnifyingglass") -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(.system(size: 36)).foregroundStyle(.secondary)
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Evaluation

    /// The conformance report (or a load error) computed from the current rules file and artifact.
    private var evaluation: Result<ConformanceReport, Error> {
        Result {
            let yaml = try String(contentsOf: URL(fileURLWithPath: rulesPath), encoding: .utf8)
            let rules = try YAMLDecoder().decode(ConformanceRules.self, from: yaml)
            let evaluator = ConformanceEvaluator(
                rules: rules,
                annotationStereotypes: artifact.standardLanguageConfiguration.annotationStereotypes)
            return evaluator.evaluate(artifact)
        }
    }

    private func chooseRulesFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.yaml]
        panel.message = "Select an architecture rules file (YAML)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rulesPath = url.path
        model.updateArchitectureCheckConfiguration(
            diagramID: diagram.id, configuration: ArchitectureCheckConfiguration(rulesPath: url.path))
    }
}
