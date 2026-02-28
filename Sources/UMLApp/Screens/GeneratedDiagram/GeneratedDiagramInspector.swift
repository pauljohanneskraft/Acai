import SwiftUI
import UMLCore

/// Inspector tab choices for the generated diagram inspector.
enum GeneratedDiagramInspectorTab {
    case settings, selection
}

/// Inspector sidebar for the generated diagram view, showing configuration
/// options and details of the currently-selected nodes.
struct GeneratedDiagramInspector: View {
    @ObservedObject var viewModel: GeneratedDiagramViewModel
    @EnvironmentObject private var model: ProjectBrowserViewModel
    let diagram: GeneratedDiagram
    let artifact: CodeArtifact
    @Binding var tab: GeneratedDiagramInspectorTab

    @State private var configuration: GeneratedDiagram.Configuration?

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Settings").tag(GeneratedDiagramInspectorTab.settings)
                Text("Selection").tag(GeneratedDiagramInspectorTab.selection)
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch tab {
            case .settings:
                configurationInspector
            case .selection:
                selectionInspector
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Configuration Inspector

    private var configurationInspector: some View {
        let config = Binding<GeneratedDiagram.Configuration>(
            get: { configuration ?? diagram.configuration },
            set: { newValue in
                configuration = newValue
                model.updateGeneratedDiagramConfiguration(diagramID: diagram.id, configuration: newValue)
                viewModel.applyConfiguration(newValue, artifact: artifact)
            }
        )

        return Form {
            Section("Visibility") {
                Toggle("Show Properties", isOn: config.showProperties)
                Toggle("Show Methods", isOn: config.showMethods)
                Toggle("Show Enum Cases", isOn: config.showEnumCases)

                Picker("Min Access Level", selection: config.minimumAccessLevel) {
                    Text("All").tag(AccessLevel?.none)
                    ForEach([AccessLevel.public, .internal, .private], id: \.self) { level in
                        Text(level.rawValue).tag(AccessLevel?.some(level))
                    }
                }
            }

            Section("Relationships") {
                Toggle("Show Relationships", isOn: config.showRelationships)
                if config.wrappedValue.showRelationships {
                    Toggle("Inheritance", isOn: config.showInheritance)
                    Toggle("Composition", isOn: config.showComposition)
                    Toggle("Dependency", isOn: config.showDependency)
                }
            }

            Section("Layout") {
                Toggle("Group by Directory", isOn: config.groupByDirectory)
                Toggle("Show External Types", isOn: config.showExternalTypes)
            }

            Section("Dart") {
                Toggle("Hide Generated Types", isOn: config.hideGeneratedDartTypes)
                Text("Hides types from .freezed.dart, .g.dart and other code-generated files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Selection Inspector

    @ViewBuilder
    private var selectionInspector: some View {
        if viewModel.selectedNodeIDs.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "cursorarrow.click")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("Select a node to inspect")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(Array(viewModel.selectedNodeIDs), id: \.self) { nodeID in
                    if let node = viewModel.nodes.first(where: { $0.id == nodeID }) {
                        Section(node.name) {
                            LabeledContent("Kind", value: node.kind.rawValue)
                            if !node.properties.isEmpty {
                                DisclosureGroup("Properties (\(node.properties.count))") {
                                    ForEach(node.properties) { prop in
                                        Text(prop.displayText)
                                            .font(.caption.monospaced())
                                    }
                                }
                            }
                            if !node.methods.isEmpty {
                                DisclosureGroup("Methods (\(node.methods.count))") {
                                    ForEach(node.methods) { method in
                                        Text(method.displayText)
                                            .font(.caption.monospaced())
                                    }
                                }
                            }

                            // Position info
                            if let pos = viewModel.nodePositions[nodeID] {
                                LabeledContent("Position") {
                                    Text("(\(Int(pos.x)), \(Int(pos.y)))")
                                        .font(.caption.monospaced())
                                }
                            }
                            let size = viewModel.effectiveSize(for: nodeID)
                            LabeledContent("Size") {
                                Text("\(Int(size.width)) x \(Int(size.height))")
                                    .font(.caption.monospaced())
                            }

                            // Show edges for this node
                            let relatedEdges = viewModel.edges.filter {
                                $0.sourceID == nodeID || $0.targetID == nodeID
                            }
                            if !relatedEdges.isEmpty {
                                DisclosureGroup("Relationships (\(relatedEdges.count))") {
                                    ForEach(relatedEdges) { edge in
                                        HStack {
                                            Text(edge.kind.rawValue)
                                                .font(.caption)
                                            Spacer()
                                            let otherID = edge.sourceID == nodeID
                                                ? edge.targetID : edge.sourceID
                                            Text(otherID)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}
