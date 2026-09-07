import SwiftUI
import AcaiQuality
import AcaiCore
import UniformTypeIdentifiers

/// Authors a codebase's code-quality check. The user either defines the rules here (a form bound to a
/// working `QualityRules`, saved to an app-managed YAML) or points at an external YAML file. The
/// "defined here" vs "external" choice is transient UI state — what gets persisted is just a path.
struct QualityCheckEditorSheet: View {
    let codebaseID: UUID
    let artifact: CodeArtifact

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @Environment(\.dismiss) private var dismiss

    private enum Source: Hashable {
        case definedHere
        case externalFile
    }

    @State private var source: Source = .definedHere
    @State private var rules = QualityRules()
    @State private var externalPath = ""
    @State private var externalBookmark: SecurityScopedBookmark?
    @State private var loaded = false
    @State private var isChoosingFile = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(.app("View.QualityCheckEditorSheet.Rules"), selection: $source) {
                    Text(.app("View.QualityCheckEditorSheet.DefinedHere")).tag(Source.definedHere)
                    Text(.app("View.QualityCheckEditorSheet.ExternalYAMLFile")).tag(Source.externalFile)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding()
                Divider()
                content
            }
            #if os(macOS)
            .frame(maxWidth: 640, maxHeight: 560)
            #endif
            .navigationTitle(.app("View.QualityCheckEditorSheet.CodeQualityCheck"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.app("View.QualityCheckEditorSheet.Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(.app("View.QualityCheckEditorSheet.Save"), action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(source == .externalFile && externalPath.isEmpty)
                }
            }
            .onAppear(perform: loadInitialState)
            .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.yaml]) { result in
                guard let url = try? result.get() else { return }
                guard url.startAccessingSecurityScopedResource() else {
                    model.store.report(.app("Error.ScopedResourceAccess.Denied \(url.path)"))
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                externalPath = url.path
                // A bookmark that silently failed to mint is what breaks access after relaunch,
                // so report it rather than storing `nil`.
                do {
                    externalBookmark = try SecurityScopedBookmark(resolving: url)
                } catch {
                    externalBookmark = nil
                    model.store.report(
                        .app("Error.ScopedResourceAccess.BookmarkFailed \(url.path) \(error.localizedDescription)"))
                }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch source {
        case .definedHere:
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    QualityRulesEditor(rules: $rules)
                    Divider()
                    Text(.app("View.QualityCheckEditorSheet.Preview")).font(.headline)
                    QualityCheckReportView(report: rules.report(for: artifact))
                }
                .padding()
            }
        case .externalFile:
            externalContent
        }
    }

    @ViewBuilder
    private var externalContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                (externalPath.isEmpty
                    ? Text(.app("View.QualityCheckEditorSheet.NoFileSelected"))
                    : Text(verbatim: (externalPath as NSString).abbreviatingWithTildeInPath))
                    .foregroundStyle(externalPath.isEmpty ? .secondary : .primary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button(.app("View.QualityCheckEditorSheet.Choose")) { isChoosingFile = true }
            }
            Divider()
            externalPreview
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var externalPreview: some View {
        if externalPath.isEmpty {
            QualityCheckPlaceholder(text: .app("View.QualityCheckEditorSheet.ChooseYAMLRulesFile"))
        } else {
            switch externalRules {
            case .success(let rules):
                ScrollView { QualityCheckReportView(report: rules.report(for: artifact)) }
            case .failure(let error):
                QualityCheckPlaceholder(
                    text: .app("View.QualityCheckEditorSheet.CouldNotLoadRules \(error.localizedDescription)"),
                    systemImage: "exclamationmark.triangle")
            }
        }
    }

    // MARK: - Actions

    private func loadInitialState() {
        guard !loaded else { return }
        loaded = true
        let path = model.codebase(for: codebaseID)?.qualityCheck?.rulesPath ?? ""
        if !path.isEmpty, !model.store.isManaged(path: path) {
            source = .externalFile
            externalPath = path
            externalBookmark = model.codebase(for: codebaseID)?.qualityCheck?.securityScopedBookmark
        } else {
            source = .definedHere
            rules = model.editing.loadEditableRules(codebaseID: codebaseID)
        }
    }

    private func save() {
        switch source {
        case .definedHere:
            model.editing.saveAuthoredRules(codebaseID: codebaseID, rules: rules)
        case .externalFile:
            guard !externalPath.isEmpty else { return }
            model.editing.setQualityCheckRulesPath(
                codebaseID: codebaseID, path: externalPath, securityScopedBookmark: externalBookmark)
        }
        dismiss()
    }

    private var externalRules: Result<QualityRules, Error> {
        Result {
            try QualityCheckConfiguration(rulesPath: externalPath, securityScopedBookmark: externalBookmark)
                .loadRules()
        }
    }
}
