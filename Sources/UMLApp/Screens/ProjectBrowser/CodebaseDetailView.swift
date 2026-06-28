import SwiftUI
import UMLCore
import UMLDiagram

/// Main content area view displayed when a codebase is selected in the sidebar.
/// Shows statistics, types, relationships, and diagram generation buttons.
struct CodebaseDetailView: View {
    let codebaseID: UUID
    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var isIndexing = false
    /// Set when the user clicks "Sequence Diagram"; drives the configuration popup.
    @State private var sequenceConfigContext: ConfigContext?
    /// Set when the user clicks "State Diagram"; drives the variable-selection popup.
    @State private var stateConfigContext: ConfigContext?
    /// Set when the user clicks "Call Graph"; drives the scope-selection popup.
    @State private var callGraphConfigContext: ConfigContext?
    /// The detail pane's current content width, used to lay out the diagram/statistics card grids so
    /// they fill the full width and wrap to more rows only when space runs out.
    @State private var contentWidth: CGFloat = 0
    /// The ranked drill-down presented when a statistics card is tapped.
    @State private var statisticDetail: StatisticDetail?
    /// Uniform card heights per grid (each = the tallest card in that grid), so cards never differ.
    @State private var statCardHeight: CGFloat = 0
    @State private var diagramCardHeight: CGFloat = 0

    /// Identifies the codebase a pending diagram configuration belongs to.
    private struct ConfigContext: Identifiable {
        let projectID: UUID
        let codebaseID: UUID
        var id: UUID { codebaseID }
    }

    var codebase: Codebase? {
        model.codebase(for: codebaseID)
    }

    var artifact: CodeArtifact? {
        model.artifact(for: codebaseID)
    }

    private var projectID: UUID? {
        model.projectID(for: codebaseID)
    }

    var body: some View {
        if let codebase {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerSection(codebase: codebase)
                    Divider()

                    if let artifact {
                        diagramsSection(codebase: codebase, artifact: artifact)
                        Divider()
                        CodebaseAnalysesSection(codebase: codebase, artifact: artifact)
                        Divider()
                        statisticsSection(artifact: artifact)
                        Divider()
                        CodebaseTypesSection(codebase: codebase, artifact: artifact)
                        Divider()
                        if !artifact.freestandingFunctions.isEmpty {
                            CodebaseFunctionsSection(codebase: codebase, artifact: artifact)
                            Divider()
                        }
                        if !artifact.globalVariables.isEmpty {
                            CodebaseGlobalsSection(codebase: codebase, artifact: artifact)
                            Divider()
                        }
                        CodebaseRelationshipsSection(artifact: artifact)
                    } else {
                        notIndexedSection(codebase: codebase)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
            }
            .sheet(item: $sequenceConfigContext) { context in
                sequenceConfigSheet(for: context)
            }
            .sheet(item: $stateConfigContext) { context in
                stateConfigSheet(for: context)
            }
            .sheet(item: $callGraphConfigContext) { context in
                callGraphConfigSheet(for: context)
            }
            .sheet(item: $statisticDetail) { detail in
                StatisticDetailSheet(detail: detail)
            }
        } else {
            Text("Codebase not found")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Header

    private func headerSection(codebase: Codebase) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "folder")
                    .font(.title)
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Codebase Name", text: Binding(
                        get: { codebase.name },
                        set: { model.updateCodebase(id: codebase.id, name: $0) }
                    ))
                    .font(.title2.bold())
                    .textFieldStyle(.plain)

                    Text((codebase.directoryPath as NSString).abbreviatingWithTildeInPath)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer()

                indexStatus(codebase: codebase)

                Button {
                    isIndexing = true
                    Task {
                        await model.reindex(codebaseID: codebase.id)
                        isIndexing = false
                    }
                } label: {
                    Label("Reindex", systemImage: "arrow.clockwise")
                }
                .disabled(isIndexing)

                exportButtons(codebase: codebase)
            }
        }
        .padding()
    }

    private func indexStatus(codebase: Codebase) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let date = codebase.lastIndexed {
                Text("Last indexed: \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if codebase.hasParseErrors {
                Label(
                    "\(codebase.parseDiagnosticCount) syntax issue(s) detected",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .help("Some files could not be fully parsed; the diagram may be incomplete.")
            }
        }
    }

    @ViewBuilder
    private func exportButtons(codebase: Codebase) -> some View {
        Button {
            model.exportDOT(for: codebase.id)
        } label: {
            Label("Export DOT", systemImage: "square.and.arrow.up")
        }

        Button {
            model.exportMermaid(for: codebase.id)
        } label: {
            Label("Export Mermaid", systemImage: "square.and.arrow.up")
        }
    }
}

// Statistics, diagram buttons, and their layout helpers — kept in an extension so the main type body
// stays within SwiftLint's `type_body_length`.
extension CodebaseDetailView {

    // MARK: - Statistics

    private func statisticsSection(artifact: CodeArtifact) -> some View {
        let metrics = artifact.computeMetrics()
        return VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)
                .padding(.horizontal)

            LazyVGrid(columns: cardColumns(count: 4), spacing: 12) {
                moduleMetricCard(
                    MetricVisual(title: "Instability", icon: "tornado", color: .orange, blurb: Self.instabilityBlurb),
                    descriptor: "Most unstable", modules: metrics.modules)
                typeMetricCard(
                    MetricVisual(title: "Inheritance Depth", icon: "arrow.down.to.line", color: .blue,
                                 blurb: Self.inheritanceDepthBlurb),
                    by: \.depthOfInheritance, descriptor: "Deepest", types: metrics.types)
                typeMetricCard(
                    MetricVisual(title: "Fan-out", icon: "arrow.up.right", color: .purple, blurb: Self.fanOutBlurb),
                    by: \.fanOut, descriptor: "Most coupled", types: metrics.types)
                typeMetricCard(
                    MetricVisual(title: "Fan-in", icon: "arrow.down.left", color: .green, blurb: Self.fanInBlurb),
                    by: \.fanIn, descriptor: "Hotspot", types: metrics.types)
            }
            .padding(.horizontal)
            .onPreferenceChange(CardHeightPreferenceKey.self) { height in
                if abs(statCardHeight - height) > 0.5 { statCardHeight = height }
            }
        }
        .padding(.vertical, 12)
    }

    /// Title, icon, tint, and explanation for a statistics card, bundled so the card builders stay
    /// within the parameter limit.
    private struct MetricVisual {
        let title: String
        let icon: String
        let color: Color
        let blurb: String
    }

    static let instabilityBlurb =
        "I = Ce / (Ca + Ce): how exposed a module is to change from its dependencies. "
        + "0% = stable (depended upon, depends on little); 100% = unstable (depends outward, nothing "
        + "depends on it). Neither is inherently bad — foundational modules should be stable, leaf/app "
        + "modules unstable."
    static let inheritanceDepthBlurb =
        "Longest inheritance/conformance chain for a type. 0–2 is easy to follow; deep chains (>5) are "
        + "a complexity smell."
    static let fanOutBlurb =
        "How many other types this type depends on. High fan-out means many responsibilities — harder "
        + "to change and test, and a candidate for splitting."
    static let fanInBlurb =
        "How many types depend on this type. High fan-in marks a core/hub type; expected for shared "
        + "models, but keep them stable and well-tested since changes ripple widely."

    /// A card for a per-type metric: max/avg with every type achieving the max named in the caption.
    /// Tapping opens the full ranked list (`typeDetail`).
    private func typeMetricCard(
        _ visual: MetricVisual,
        by keyPath: KeyPath<CodeMetrics.TypeMetric, Int>,
        descriptor: String, types: [CodeMetrics.TypeMetric]
    ) -> MetricStatCard {
        let summary = MetricSummary(types) { Double($0[keyPath: keyPath]) }
        let detail = typeDetail(visual.title, visual.blurb, types, by: keyPath)
        return MetricStatCard(
            title: visual.title,
            icon: visual.icon,
            color: visual.color,
            primary: "max \(Int(summary.maximum))",
            secondary: String(format: "avg %.1f", summary.average),
            exemplar: caption(descriptor, summary.exemplars.map { shortName($0.name) }),
            uniformHeight: statCardHeight,
            onTap: detail.rows.isEmpty ? nil : { statisticDetail = detail })
    }

    /// A card for the per-module instability metric, rendered as a percentage with every most-unstable
    /// module named. Tapping opens the ranked module list (`moduleDetail`).
    private func moduleMetricCard(
        _ visual: MetricVisual,
        descriptor: String, modules: [CodeMetrics.ModuleCoupling]
    ) -> MetricStatCard {
        let summary = MetricSummary(modules) { $0.instability }
        let detail = moduleDetail(visual.title, visual.blurb, modules)
        return MetricStatCard(
            title: visual.title,
            icon: visual.icon,
            color: visual.color,
            primary: String(format: "max %.0f%%", summary.maximum * 100),
            secondary: String(format: "avg %.0f%%", summary.average * 100),
            exemplar: caption(descriptor, summary.exemplars.map(\.name)),
            uniformHeight: statCardHeight,
            onTap: detail.rows.isEmpty ? nil : { statisticDetail = detail })
    }

    /// "`descriptor.lowercased()`: name, name, …" — or `nil` when there are no exemplars.
    private func caption(_ descriptor: String, _ names: [String]) -> String? {
        names.isEmpty ? nil : "\(descriptor.lowercased()): \(names.joined(separator: ", "))"
    }

    // MARK: - Card grid layout

    /// Flexible columns sized so `count` cards fill the full content width, wrapping to more rows only
    /// when the pane is too narrow to fit them all at `target` width. Capping the column count at the
    /// card count (rather than `.adaptive`) keeps the row full-width instead of leaving empty trailing
    /// columns when there are fewer cards than would fit.
    private func cardColumns(count: Int, target: CGFloat = 200) -> [GridItem] {
        let usableWidth = contentWidth - 32  // outer .padding(.horizontal) on each side
        let fitting = max(1, Int((usableWidth + 12) / (target + 12)))
        let columns = max(1, min(count, fitting))
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: columns)
    }

    // MARK: - Diagrams

    private func diagramsSection(codebase: Codebase, artifact: CodeArtifact) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagrams")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 12)

            LazyVGrid(columns: cardColumns(count: DiagramType.allCases.count), spacing: 12) {
                ForEach(DiagramType.allCases) { type in
                    diagramButton(codebase: codebase, type: type)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
            .onPreferenceChange(CardHeightPreferenceKey.self) { height in
                if abs(diagramCardHeight - height) > 0.5 { diagramCardHeight = height }
            }
        }
    }

    /// A diagram type button. Each click creates a new generated diagram of that type; sequence
    /// and state diagrams first open their configuration popup (entry point / variable selection).
    private func diagramButton(codebase: Codebase, type: DiagramType) -> some View {
        Button {
            guard let projectID else { return }
            if type == .sequenceDiagram {
                sequenceConfigContext = ConfigContext(projectID: projectID, codebaseID: codebase.id)
                return
            }
            if type == .stateDiagram {
                stateConfigContext = ConfigContext(projectID: projectID, codebaseID: codebase.id)
                return
            }
            if type == .callGraph {
                callGraphConfigContext = ConfigContext(projectID: projectID, codebaseID: codebase.id)
                return
            }
            if let id = model.addGeneratedDiagram(
                to: projectID,
                codebaseID: codebase.id,
                content: GeneratedDiagram.Content(type: type)
            ) {
                model.selection = .generatedDiagram(id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: type.systemImage)
                    .font(.title2.bold())
                Text(type.displayName)
                    .font(.title3.bold())
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: CardHeightPreferenceKey.self, value: proxy.size.height)
            })
            .frame(minHeight: diagramCardHeight > 0 ? diagramCardHeight : nil, alignment: .topLeading)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Not Indexed

    private func notIndexedSection(codebase: Codebase) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("This codebase has not been indexed yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                isIndexing = true
                Task {
                    await model.reindex(codebaseID: codebase.id)
                    isIndexing = false
                }
            } label: {
                Label("Index Now", systemImage: "arrow.clockwise")
            }
            .disabled(isIndexing)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Diagram configuration sheets

extension CodebaseDetailView {

    /// The state-diagram configuration popup, presented when "State Diagram" is clicked.
    @ViewBuilder
    private func stateConfigSheet(for context: ConfigContext) -> some View {
        if let artifact = model.artifact(for: context.codebaseID) {
            StateConfigSheet(
                artifact: artifact,
                onCancel: { stateConfigContext = nil },
                onCreate: { config in
                    if let id = model.addGeneratedDiagram(
                        to: context.projectID,
                        codebaseID: context.codebaseID,
                        content: .stateDiagram(config)
                    ) {
                        model.selection = .generatedDiagram(id)
                    }
                    stateConfigContext = nil
                }
            )
        }
    }

    /// The call-graph scope popup, presented when "Call Graph" is clicked.
    @ViewBuilder
    private func callGraphConfigSheet(for context: ConfigContext) -> some View {
        if let artifact = model.artifact(for: context.codebaseID) {
            CallGraphConfigSheet(
                artifact: artifact,
                onCancel: { callGraphConfigContext = nil },
                onCreate: { scope in
                    if let id = model.addGeneratedDiagram(
                        to: context.projectID,
                        codebaseID: context.codebaseID,
                        content: .callGraph(scope)
                    ) {
                        model.selection = .generatedDiagram(id)
                    }
                    callGraphConfigContext = nil
                }
            )
        }
    }

    /// The sequence-diagram configuration popup, presented when "Sequence Diagram" is clicked.
    @ViewBuilder
    private func sequenceConfigSheet(for context: ConfigContext) -> some View {
        if let artifact = model.artifact(for: context.codebaseID) {
            SequenceConfigSheet(
                artifact: artifact,
                onCancel: { sequenceConfigContext = nil },
                onCreate: { config in
                    if let id = model.addGeneratedDiagram(
                        to: context.projectID,
                        codebaseID: context.codebaseID,
                        content: .sequenceDiagram(config)
                    ) {
                        model.selection = .generatedDiagram(id)
                    }
                    sequenceConfigContext = nil
                }
            )
        }
    }
}
