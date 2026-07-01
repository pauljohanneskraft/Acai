import AppKit
import SwiftUI
import UMLConformance
import UMLCore
import UniformTypeIdentifiers

/// Authors a codebase's architecture check. The user either defines the rules here (a form bound to a
/// working `ConformanceRules`, saved to an app-managed YAML) or points at an external YAML file. The
/// "defined here" vs "external" choice is transient UI state — what gets persisted is just a path.
struct ArchitectureCheckEditorSheet: View {
    let codebaseID: UUID
    let artifact: CodeArtifact

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @Environment(\.dismiss) private var dismiss

    private enum Source: Hashable {
        case definedHere
        case externalFile
    }

    @State private var source: Source = .definedHere
    @State private var rules = ConformanceRules()
    @State private var externalPath = ""
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("Rules", selection: $source) {
                Text("Defined here").tag(Source.definedHere)
                Text("External YAML file").tag(Source.externalFile)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()
            Divider()
            content
        }
        .frame(minWidth: 640, minHeight: 560)
        .onAppear(perform: loadInitialState)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("Architecture Check", systemImage: "checkmark.shield")
                .font(.title3.bold())
            Spacer()
            Button("Cancel") { dismiss() }
            Button("Save", action: save)
                .keyboardShortcut(.defaultAction)
                .disabled(source == .externalFile && externalPath.isEmpty)
        }
        .padding()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch source {
        case .definedHere:
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ConformanceRulesEditor(rules: $rules)
                    Divider()
                    Text("Preview").font(.headline)
                    ArchitectureCheckReportView(rules: rules, artifact: artifact)
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
                Text(externalPath.isEmpty ? "No file selected"
                     : (externalPath as NSString).abbreviatingWithTildeInPath)
                    .foregroundStyle(externalPath.isEmpty ? .secondary : .primary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose…", action: chooseFile)
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
            ArchitectureCheckPlaceholder(text: "Choose a YAML rules file to validate this codebase against.")
        } else {
            switch externalRules {
            case .success(let rules):
                ScrollView { ArchitectureCheckReportView(rules: rules, artifact: artifact) }
            case .failure(let error):
                ArchitectureCheckPlaceholder(
                    text: "Could not load rules: \(error.localizedDescription)",
                    systemImage: "exclamationmark.triangle")
            }
        }
    }

    // MARK: - Actions

    private func loadInitialState() {
        guard !loaded else { return }
        loaded = true
        let path = model.codebase(for: codebaseID)?.architectureCheck?.rulesPath ?? ""
        if !path.isEmpty, !model.store.isManaged(path: path) {
            source = .externalFile
            externalPath = path
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
            model.editing.setArchitectureCheckRulesPath(codebaseID: codebaseID, path: externalPath)
        }
        dismiss()
    }

    /// The decoded rules at the chosen external path (or the load error), for the preview.
    private var externalRules: Result<ConformanceRules, Error> {
        Result { try ArchitectureCheckConfiguration(rulesPath: externalPath).loadRules() }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.yaml]
        panel.message = "Select an architecture rules file (YAML)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        externalPath = url.path
    }
}

extension Result where Failure == Error {
    /// Wraps a throwing expression in a `Result`, mirroring `Result { try … }` but usable in a
    /// `switch` expression position.
    init(catching body: () throws -> Success) {
        do { self = .success(try body()) } catch { self = .failure(error) }
    }
}
