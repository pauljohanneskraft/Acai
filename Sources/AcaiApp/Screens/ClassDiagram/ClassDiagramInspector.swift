import SwiftUI
import AcaiCore
import AcaiDiff
import AcaiLibrary
import AcaiRender

enum ClassDiagramSidebarTab {
    case settings, inspector
}

struct ClassDiagramSidebar: View {
    @ObservedObject var viewModel: ClassDiagramViewModel
    @EnvironmentObject private var model: ProjectBrowserViewModel
    let diagram: GeneratedDiagram
    let artifact: CodeArtifact
    @Binding var tab: ClassDiagramSidebarTab
    /// Re-layout/Save as Freeform/Export Image moved here from the toolbar; the canvas state
    /// (scale/offset) they need stays owned by `ClassDiagramView`, so it hands in closures instead.
    let onRelayout: () -> Void
    let onSaveAsFreeform: () -> Void
    let onExportImage: () -> Void

    var body: some View {
        content
    }

    private var content: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text(.app("View.ClassDiagramSidebar.Settings")).tag(ClassDiagramSidebarTab.settings)
                Text(.app("View.ClassDiagramSidebar.Inspector")).tag(ClassDiagramSidebarTab.inspector)
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch tab {
            case .settings:
                configurationInspector
                    .accessibilityIdentifier("diagram.sidebarContent.settings")
            case .inspector:
                selectionInspector
                    .accessibilityIdentifier("diagram.sidebarContent.inspector")
            }
        }
        .background {
            #if os(macOS)
            Color(nsColor: .controlBackgroundColor)
            #else
            Color(uiColor: .secondarySystemBackground)
            #endif
        }
    }

    // MARK: - Configuration Inspector

    private var editor: ClassDiagramConfigEditor {
        ClassDiagramConfigEditor(model: model, viewModel: viewModel, diagramID: diagram.id, artifact: artifact)
    }

    private var configurationInspector: some View {
        let editor = self.editor
        let config = Binding<ClassDiagramConfiguration>(
            get: { viewModel.configuration },
            set: { newValue in editor.mutate { $0 = newValue } }
        )
        let typeNames = Array(Set(artifact.flattened().map(\.name))).sorted()

        return Form {
            Section(.app("View.ClassDiagramSidebar.Visibility")) {
                Toggle(.app("View.ClassDiagramSidebar.ShowProperties"), isOn: editor.globalVisibility(
                    \.showProperties, override: \.propertyVisibility))
                Toggle(.app("View.ClassDiagramSidebar.ShowMethods"), isOn: editor.globalVisibility(
                    \.showMethods, override: \.methodVisibility))
                Toggle(.app("View.ClassDiagramSidebar.ShowEnumCases"), isOn: editor.globalVisibility(
                    \.showEnumCases, override: \.enumCaseVisibility))
                Text(.app("View.ClassDiagramSidebar.TogglingResetsPerType"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(.app("View.ClassDiagramSidebar.MinAccessLevel"), selection: config.minimumAccessLevel) {
                    Text(.app("View.ClassDiagramSidebar.All")).tag(AccessLevel?.none)
                    ForEach([AccessLevel.public, .internal, .private], id: \.self) { level in
                        Text(verbatim: level.rawValue).tag(AccessLevel?.some(level))
                    }
                }
            }

            DiagramFilterSection(
                filter: config.filter,
                codebaseID: diagram.codebaseID,
                projectID: model.projectID(for: diagram.codebaseID) ?? diagram.codebaseID,
                artifact: artifact
            )

            Section(.app("View.ClassDiagramSidebar.Relationships")) {
                Toggle(.app("View.ClassDiagramSidebar.ShowRelationships"), isOn: config.showRelationships)
                if config.wrappedValue.showRelationships {
                    Toggle(.app("View.ClassDiagramSidebar.Inheritance"), isOn: config.showInheritance)
                    Toggle(.app("View.ClassDiagramSidebar.Composition"), isOn: config.showComposition)
                    Toggle(.app("View.ClassDiagramSidebar.Dependency"), isOn: config.showDependency)
                    Toggle(.app("View.ClassDiagramSidebar.Multiplicities"), isOn: config.showMultiplicities)
                }
            }

            Section(.app("View.ClassDiagramSidebar.Stereotypes")) {
                Toggle(.app("View.ClassDiagramSidebar.AnnotationStereotypes"), isOn: config.showAnnotationStereotypes)
                Text(.app("View.ClassDiagramSidebar.ShowsEntitySimilarStereotypes"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(.app("View.ClassDiagramSidebar.Layout")) {
                Picker(.app("View.ClassDiagramSidebar.Grouping"), selection: config.grouping) {
                    Text(.app("View.ClassDiagramSidebar.None")).tag(ClassDiagramConfiguration.Grouping.none)
                    Text(.app("View.ClassDiagramSidebar.Directory")).tag(ClassDiagramConfiguration.Grouping.directory)
                    Text(.app("View.ClassDiagramSidebar.Product")).tag(ClassDiagramConfiguration.Grouping.product)
                }
                Toggle(.app("View.ClassDiagramSidebar.ShowExternalTypes"), isOn: config.showExternalTypes)
                Button(action: onRelayout) {
                    Label(.app("View.ClassDiagramSidebar.ReLayout"), systemImage: "rectangle.3.group")
                }
                .help(.app("View.ClassDiagramSidebar.ReRunAutomaticLayout"))
                .accessibilityIdentifier("diagram.relayoutButton")
            }

            FocusSection(configuration: config, typeNames: typeNames)

            // Shown only for languages that declare a generated-code filter; the label and
            // explanation come from that filter, so the app names no language itself.
            if let filter = artifact.standardLanguageResolver.defaultConfiguration.generatedCodeFilter {
                Section(filter.displayName) {
                    Toggle(.app("View.ClassDiagramSidebar.HideGeneratedTypes"), isOn: config.hideGeneratedTypes)
                    Text(verbatim: filter.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(.app("View.ClassDiagramSidebar.Export")) {
                Button(action: onSaveAsFreeform) {
                    Label(.app("View.ClassDiagramSidebar.SaveFreeform"), systemImage: "document.on.document")
                }
                .help(.app("View.ClassDiagramSidebar.SaveCopyEditableFreeform"))
                .accessibilityIdentifier("diagram.saveAsFreeformButton")
                Button(action: onExportImage) {
                    Label(.app("View.ClassDiagramSidebar.ExportImage"), systemImage: "photo")
                }
                .help(.app("View.ClassDiagramSidebar.ExportDiagramImage"))
                .accessibilityIdentifier("diagram.exportImageButton")
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
                Text(.app("View.ClassDiagramSidebar.SelectNodeInspect"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.selectedNodeIDs.count > 1 {
            multiSelectionInspector
        } else {
            List {
                ForEach(Array(viewModel.selectedNodeIDs), id: \.self) { nodeID in
                    if let node = viewModel.nodes.first(where: { $0.id == nodeID }) {
                        Section(node.name) {
                            LabeledContent {
                                Text(verbatim: node.kind.rawValue)
                            } label: {
                                Text(.app("View.ClassDiagramSidebar.Kind"))
                            }

                            if let change = viewModel.typeChange(for: node) {
                                whatChangedSection(change)
                            }

                            DisclosureGroup {
                                Toggle(.app("View.ClassDiagramSidebar.ShowProperties"), isOn: editor.typeVisibility(
                                    nodeID, override: \.propertyVisibility, default: \.showProperties))
                                Toggle(.app("View.ClassDiagramSidebar.ShowMethods"), isOn: editor.typeVisibility(
                                    nodeID, override: \.methodVisibility, default: \.showMethods))
                                if node.kind == .enum {
                                    Toggle(.app("View.ClassDiagramSidebar.ShowEnumCases"), isOn: editor.typeVisibility(
                                        nodeID, override: \.enumCaseVisibility, default: \.showEnumCases))
                                }
                            } label: {
                                Text(.app("View.ClassDiagramSidebar.Visibility"))
                            }

                            if !node.properties.isEmpty {
                                DisclosureGroup {
                                    ForEach(node.properties) { prop in
                                        MemberRowView(item: prop.displayItem, compact: false)
                                    }
                                } label: {
                                    Text(.app("View.ClassDiagramSidebar.Properties \(node.properties.count)"))
                                }
                            }
                            if !node.methods.isEmpty {
                                DisclosureGroup {
                                    ForEach(node.methods) { method in
                                        MemberRowView(item: method.displayItem, compact: false)
                                    }
                                } label: {
                                    Text(.app("View.ClassDiagramSidebar.Methods \(node.methods.count)"))
                                }
                            }

                            if let pos = viewModel.nodePositions[nodeID] {
                                LabeledContent {
                                    Text(verbatim: "(\(Int(pos.x)), \(Int(pos.y)))")
                                        .font(.caption.monospaced())
                                } label: {
                                    Text(.app("View.ClassDiagramSidebar.Position"))
                                }
                            }
                            let size = viewModel.effectiveSize(for: nodeID)
                            LabeledContent {
                                Text(verbatim: "\(Int(size.width)) x \(Int(size.height))")
                                    .font(.caption.monospaced())
                            } label: {
                                Text(.app("View.ClassDiagramSidebar.Size"))
                            }

                            let relatedEdges = viewModel.edges.filter {
                                $0.sourceID == nodeID || $0.targetID == nodeID
                            }
                            if !relatedEdges.isEmpty {
                                DisclosureGroup {
                                    ForEach(relatedEdges) { edge in
                                        HStack {
                                            Text(verbatim: edge.kind.rawValue)
                                                .font(.caption)
                                            Spacer()
                                            let otherID = edge.sourceID == nodeID
                                                ? edge.targetID : edge.sourceID
                                            Text(verbatim: otherID)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                } label: {
                                    Text(.app("View.ClassDiagramSidebar.RelationshipsCount \(relatedEdges.count)"))
                                }
                            }
                            VStack(alignment: .center) {
                                revealInFinderButton(node: node)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var selectedNodes: [GeneratedDiagramNode] {
        viewModel.nodes.filter { viewModel.selectedNodeIDs.contains($0.id) }.sorted { $0.name < $1.name }
    }

    private var selectedNodesShowMembers: Bool {
        viewModel.configuration.showsMembers(forTypeIDs: selectedNodes.map(\.id))
    }

    private var multiSelectionInspector: some View {
        MultiSelectionInspector(
            items: selectedNodes,
            title: { Text(.app("View.ClassDiagramSidebar.NodeInflectTrueSelected \($0)")) },
            rowIcon: { _ in "cube" },
            rowLabel: \.name,
            rowDetail: { $0.kind.rawValue },
            onSelect: { viewModel.selectNode($0, extending: false) },
            bulkAction: .init(
                label: selectedNodesShowMembers ? "Hide Members" : "Show Members",
                systemImage: selectedNodesShowMembers ? "eye.slash" : "eye",
                role: nil,
                action: toggleSelectedNodesVisibility
            )
        )
    }

    /// Shows or hides properties+methods for every selected type in one mutation (one persist,
    /// one live rebuild), reusing `ClassDiagramConfigEditor`'s per-type override mechanism —
    /// the same one the single-node inspector's "Visibility" toggles write to.
    private func toggleSelectedNodesVisibility() {
        let ids = selectedNodes.map(\.id)
        editor.mutate { $0.setMemberVisibility(!$0.showsMembers(forTypeIDs: ids), forTypeIDs: ids) }
    }

}

private extension ClassDiagramSidebar {
    @ViewBuilder
    func whatChangedSection(_ change: TypeChange) -> some View {
        DisclosureGroup {
            if let kindChange = change.kindChange {
                LabeledContent {
                    Text(verbatim: "\(kindChange.before.rawValue) → \(kindChange.after.rawValue)")
                        .font(.caption.monospaced())
                } label: {
                    Text(.app("View.ClassDiagramSidebar.Kind"))
                }
            }
            if let accessChange = change.accessChange {
                LabeledContent {
                    Text(verbatim: "\(accessChange.before.rawValue) → \(accessChange.after.rawValue)")
                        .font(.caption.monospaced())
                } label: {
                    Text(.app("View.ClassDiagramSidebar.Access"))
                }
            }
            ForEach(change.changedMembers, id: \.name) { memberChange in
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "~ \(memberChange.name)")
                        .font(.caption.monospaced())
                    Text(verbatim: memberChange.before)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .strikethrough()
                    Text(verbatim: memberChange.after)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(change.addedMembers, id: \.self) { member in
                Text(verbatim: "+ \(member)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.green)
            }
            ForEach(change.removedMembers, id: \.self) { member in
                Text(verbatim: "− \(member)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.red)
            }
        } label: {
            Text(.app("View.ClassDiagramSidebar.WhatChanged"))
        }
        .accessibilityIdentifier("diagram.inspector.whatChanged")
    }

    @ViewBuilder
    func revealInFinderButton(node: GeneratedDiagramNode) -> some View {
        #if os(macOS)
        // Resolved in the action, not the body: resolution touches the filesystem and opens a
        // security scope, which a view body must not do on every pass.
        if let type = artifact.types.first(where: { $0.id == node.id }),
           let filePath = type.location?.filePath {
            Button {
                FinderReveal(
                    codebase: viewModel.codebase, relativePath: filePath,
                    onFailure: { [store = model.store] in
                        store.report(.app("Error.FinderReveal.Failed \($0.localizedDescription)"))
                    }
                ).reveal()
            } label: {
                Label(.app("View.ClassDiagramSidebar.RevealFinder"), systemImage: "finder")
            }
        }
        #endif
    }
}

private struct FocusSection: View {
    @Binding var configuration: ClassDiagramConfiguration
    let typeNames: [String]

    var body: some View {
        Section(.app("View.FocusSection.Focus")) {
            Toggle(.app("View.FocusSection.FocusClass"), isOn: focusEnabled)

            if configuration.focus != nil {
                Picker(.app("View.FocusSection.RootType"), selection: rootType) {
                    ForEach(typeNames, id: \.self) { Text(verbatim: $0).tag($0) }
                }

                Toggle(.app("View.FocusSection.LimitDepth"), isOn: depthLimited)
                if configuration.focus?.maxDepth != nil {
                    Stepper(
                        .app("View.FocusSection.Depth \(configuration.focus?.maxDepth ?? 1)"),
                        value: depthValue, in: 1...20
                    )
                }

                Picker(.app("View.FocusSection.Direction"), selection: direction) {
                    Text(.app("View.FocusSection.Dependencies")).tag(FocusConfiguration.Direction.dependencies)
                    Text(.app("View.FocusSection.Dependents")).tag(FocusConfiguration.Direction.dependents)
                    Text(.app("View.FocusSection.Both")).tag(FocusConfiguration.Direction.both)
                }

                DisclosureGroup {
                    ForEach(Relationship.Kind.allCases, id: \.self) { kind in
                        Toggle(kind.rawValue.capitalized, isOn: kindBinding(kind))
                    }
                } label: {
                    Text(.app("View.FocusSection.RelationshipKinds"))
                }

                Toggle(.app("View.FocusSection.IncludeInterconnections"), isOn: interconnections)
            }
        }
    }

    private var focusEnabled: Binding<Bool> {
        Binding(
            get: { configuration.focus != nil },
            set: { configuration.focus = $0 ? FocusConfiguration(rootTypeName: typeNames.first ?? "") : nil }
        )
    }

    private var rootType: Binding<String> {
        Binding(
            get: { configuration.focus?.rootTypeName ?? "" },
            set: { configuration.focus?.rootTypeName = $0 }
        )
    }

    private var depthLimited: Binding<Bool> {
        Binding(
            get: { configuration.focus?.maxDepth != nil },
            set: { configuration.focus?.maxDepth = $0 ? 3 : nil }
        )
    }

    private var depthValue: Binding<Int> {
        Binding(
            get: { configuration.focus?.maxDepth ?? 3 },
            set: { configuration.focus?.maxDepth = $0 }
        )
    }

    private var direction: Binding<FocusConfiguration.Direction> {
        Binding(
            get: { configuration.focus?.direction ?? .dependencies },
            set: { configuration.focus?.direction = $0 }
        )
    }

    private func kindBinding(_ kind: Relationship.Kind) -> Binding<Bool> {
        Binding(
            get: { configuration.focus?.includedRelationshipKinds.contains(kind) ?? false },
            set: { include in
                if include {
                    configuration.focus?.includedRelationshipKinds.insert(kind)
                } else {
                    configuration.focus?.includedRelationshipKinds.remove(kind)
                }
            }
        )
    }

    private var interconnections: Binding<Bool> {
        Binding(
            get: { configuration.focus?.includeInterconnections ?? true },
            set: { configuration.focus?.includeInterconnections = $0 }
        )
    }
}
