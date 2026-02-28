import SwiftUI

/// Sheet for configuring and generating a diagram from a codebase.
struct DiagramGenerationSheet: View {
    let projectID: UUID
    let codebaseID: UUID
    @EnvironmentObject private var model: ProjectBrowserViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var diagramName = ""
    @State private var selectedType: DiagramType = .classDiagram
    @State private var configuration = GeneratedDiagram.Configuration()
    @State private var isGenerating = false

    private var codebase: Codebase? {
        model.codebase(for: codebaseID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Generate Diagram").font(.title2).bold()

            if let codebase {
                Text("From: \(codebase.name)")
                    .foregroundStyle(.secondary)
            }

            Form {
                TextField("Diagram Name", text: $diagramName)

                Picker("Type", selection: $selectedType) {
                    ForEach(DiagramType.allCases) { type in
                        Label(type.displayName, systemImage: type.systemImage)
                            .tag(type)
                    }
                }

                Section("Options") {
                    Toggle("Show Properties", isOn: $configuration.showProperties)
                    Toggle("Show Methods", isOn: $configuration.showMethods)
                    Toggle("Show Enum Cases", isOn: $configuration.showEnumCases)
                    Toggle("Show Relationships", isOn: $configuration.showRelationships)

                    if configuration.showRelationships {
                        Toggle("Show Inheritance", isOn: $configuration.showInheritance)
                        Toggle("Show Composition", isOn: $configuration.showComposition)
                        Toggle("Show Dependency", isOn: $configuration.showDependency)
                    }

                    Toggle("Group by Directory", isOn: $configuration.groupByDirectory)
                    Toggle("Show External Types", isOn: $configuration.showExternalTypes)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Generate") {
                    generate()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(diagramName.isEmpty || isGenerating)
            }
        }
        .padding()
        .frame(width: 440, height: 520)
        .onAppear {
            if let name = codebase?.name {
                diagramName = "\(name) — Class Diagram"
            }
        }
        .onChange(of: selectedType) { newType in
            if let name = codebase?.name {
                diagramName = "\(name) — \(newType.displayName)"
            }
        }
    }

    private func generate() {
        isGenerating = true

        // Ensure codebase has been indexed.
        guard codebase?.hasArtifact == true else {
            // Reindex first, then generate.
            Task {
                await model.reindex(codebaseID: codebaseID)
                if let id = model.addGeneratedDiagram(
                    to: projectID,
                    codebaseID: codebaseID,
                    name: diagramName,
                    type: selectedType,
                    configuration: configuration
                ) {
                    model.selection = .diagram(id)
                }
                dismiss()
            }
            return
        }

        if let id = model.addGeneratedDiagram(
            to: projectID,
            codebaseID: codebaseID,
            name: diagramName,
            type: selectedType,
            configuration: configuration
        ) {
            model.selection = .diagram(id)
        }
        dismiss()
    }
}
