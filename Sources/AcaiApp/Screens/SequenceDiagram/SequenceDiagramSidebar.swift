import SwiftUI
import AcaiCore
import AcaiDiagram
import AcaiQuality
import AcaiRender

/// Sidebar tab choices for the sequence diagram, matching Class Diagram's closed vocabulary.
enum SequenceDiagramSidebarTab {
    case settings, inspector
}

/// Sequence Diagram's sidebar: folds `SequenceConfigSheet`'s entry-point/interface-resolution
/// fields into a live Settings tab (instead of a one-shot modal), and adds an Inspector tab showing
/// detail for the selected lifeline or message — neither existed before this pass.
///
/// Unlike Class Diagram's configuration, applying a new entry point re-runs the whole trace and
/// necessarily drops lifeline drags/undo history (`SequenceDiagramViewModel.applyConfiguration`), so
/// this can't live-bind on every keystroke the way Class Diagram's `Form` does — edits stage into a
/// local draft, applied only on an explicit "Apply" tap.
struct SequenceDiagramSidebar: View {
    @ObservedObject var viewModel: SequenceDiagramViewModel
    let codebaseID: UUID
    @Binding var tab: SequenceDiagramSidebarTab
    let onApply: (SequenceDiagramConfiguration) -> Void
    let onApplyFilter: (AcaiQuality.Selector?) -> Void
    let onSaveAsFreeform: () -> Void
    let onExportImage: () -> Void

    @EnvironmentObject private var model: ProjectBrowserViewModel

    /// The staged entry point and interface resolution, plus the option lists they are picked from.
    @State private var config: SequenceConfigModel
    @State private var typeQuery = ""
    @State private var methodQuery = ""

    init(
        viewModel: SequenceDiagramViewModel,
        artifact: CodeArtifact,
        codebaseID: UUID,
        tab: Binding<SequenceDiagramSidebarTab>,
        onApply: @escaping (SequenceDiagramConfiguration) -> Void,
        onApplyFilter: @escaping (AcaiQuality.Selector?) -> Void,
        onSaveAsFreeform: @escaping () -> Void,
        onExportImage: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.codebaseID = codebaseID
        self._tab = tab
        self.onApply = onApply
        self.onApplyFilter = onApplyFilter
        self.onSaveAsFreeform = onSaveAsFreeform
        self.onExportImage = onExportImage
        _config = State(initialValue: SequenceConfigModel(
            artifact: artifact, initial: viewModel.configuration
        ))
    }

    var body: some View {
        VStack(spacing: .zero) {
            Picker("", selection: $tab) {
                Text(.app("View.SequenceDiagramSidebar.Settings")).tag(SequenceDiagramSidebarTab.settings)
                Text(.app("View.SequenceDiagramSidebar.Inspector")).tag(SequenceDiagramSidebarTab.inspector)
            }
            .pickerStyle(.segmented)
            .padding(.spacingS)

            Divider()

            switch tab {
            case .settings:
                settingsContent
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

    // MARK: - Settings

    private var isDraftUnchanged: Bool {
        config.entryTypeName == viewModel.configuration.entryTypeName
            && config.entryMethodName == viewModel.configuration.entryMethodName
            && config.maxDepth == viewModel.configuration.maxDepth
    }

    private var settingsContent: some View {
        Form {
            Section(.app("View.SequenceDiagramSidebar.EntryPoint")) {
                Text(.app("View.SequenceDiagramSidebar.ChooseWhereTraceBegins"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent {
                    VStack(alignment: .leading, spacing: .spacingXS) {
                        PickerFilterField(text: $typeQuery)
                        Picker(.app("View.SequenceDiagramSidebar.Type"), selection: entryTypeName) {
                            Text(localized: config.freeFunctionNames.isEmpty
                                ? .app("View.SequenceDiagramSidebar.SelectEllipsis")
                                : .app("View.SequenceDiagramSidebar.NoneTopLevelFunctions")).tag("")
                            ForEach(config.callableTypeNames.filtered(by: typeQuery), id: \.self) {
                                Text(verbatim: $0).tag($0)
                            }
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("diagram.sequenceSettings.typePicker")
                    }
                } label: {
                    Text(.app("View.SequenceDiagramSidebar.Type"))
                }

                LabeledContent(config.entryTypeName.isEmpty ? "Function" : "Method") {
                    VStack(alignment: .leading, spacing: .spacingXS) {
                        PickerFilterField(text: $methodQuery)
                        Picker(.app("View.SequenceDiagramSidebar.Method"), selection: $config.entryMethodName) {
                            Text(.app("View.SequenceDiagramSidebar.Select")).tag("")
                            ForEach(config.methodNames.filtered(by: methodQuery), id: \.self) {
                                Text(verbatim: $0).tag($0)
                            }
                        }
                        .labelsHidden()
                        .disabled(config.methodNames.isEmpty)
                        .accessibilityIdentifier("diagram.sequenceSettings.methodPicker")
                    }
                }

                LabeledContent {
                    Stepper(value: $config.maxDepth, in: 1...20) {
                        Text(config.maxDepth, format: .number)
                    }
                } label: {
                    Text(.app("View.SequenceDiagramSidebar.MaxDepth"))
                }

                Button(.app("View.SequenceDiagramSidebar.Apply"), action: apply)
                    .disabled(isDraftUnchanged || !config.canAdvance)
                    .accessibilityIdentifier("diagram.sequenceSettings.applyButton")
            }

            if config.step == .resolveInterfaces {
                Section(.app("View.SequenceDiagramSidebar.ResolveInterfaces")) {
                    Text(.app("View.SequenceDiagramSidebar.TheseAbstractionsAppearAlong"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(config.mappings) { mapping in
                        LabeledContent(mapping.protocolName) {
                            Picker(mapping.protocolName, selection: selection(for: mapping.protocolName)) {
                                Text(.app("View.SequenceDiagramSidebar.LeaveAbstract")).tag(String?.none)
                                ForEach(mapping.candidates, id: \.self) { Text(verbatim: $0).tag(String?.some($0)) }
                            }
                            .labelsHidden()
                        }
                    }
                    Button(.app("View.SequenceDiagramSidebar.ApplyResolvedMapping"), action: applyResolvedMapping)
                        .accessibilityIdentifier("diagram.sequenceSettings.applyResolvedMappingButton")
                }
            }

            DiagramFilterSection(
                filter: filterBinding,
                projectID: model.projectID(for: codebaseID) ?? codebaseID
            )

            Section(.app("View.SequenceDiagramSidebar.Export")) {
                Button(action: onSaveAsFreeform) {
                    Label(.app("View.SequenceDiagramSidebar.SaveFreeform"), systemImage: "document.on.document")
                }
                .help(.app("View.SequenceDiagramSidebar.SaveCopyEditableFreeform"))
                .disabled(viewModel.isEmpty)
                .accessibilityIdentifier("diagram.saveAsFreeformButton")
                Button(action: onExportImage) {
                    Label(.app("View.SequenceDiagramSidebar.ExportImage"), systemImage: "photo")
                }
                .help(.app("View.SequenceDiagramSidebar.ExportDiagramImage"))
                .disabled(viewModel.isEmpty)
                .accessibilityIdentifier("diagram.exportImageButton")
            }
        }
        .formStyle(.grouped)
    }

    /// Seeds the rows from the mapping now in effect, which changes with each apply.
    private func apply() {
        let advance = config.advance(selectedConcreteTypes: viewModel.configuration.typeMapping)
        if case .finished(let configuration) = advance { onApply(configuration) }
    }

    private var entryTypeName: Binding<String> {
        Binding(get: { config.entryTypeName }, set: { config.selectEntryType($0) })
    }

    private func selection(for protocolName: String) -> Binding<String?> {
        Binding(
            get: { config.mappings.first { $0.id == protocolName }?.selection },
            set: { config.select($0, forAbstractionNamed: protocolName) }
        )
    }

    private var filterBinding: Binding<AcaiQuality.Selector?> {
        Binding(
            get: { viewModel.configuration.filter },
            set: { onApplyFilter($0) }
        )
    }

    private func applyResolvedMapping() {
        onApply(config.configuration)
        config.back()
    }
}
