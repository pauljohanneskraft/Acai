import Charts
import SwiftUI
import AcaiCore
import AcaiQuality

/// Read-only analysis view: churn (commits touching a file) × complexity
/// (`CodeMetrics.TypeMetric.maxCyclomaticComplexity`, maxed per file) scatter — the top-right
/// quadrant (above both medians) is the hotspot list. Loads churn asynchronously, off the main
/// actor (`HotspotViewModel.load`), so opening this screen never blocks on a git-history walk.
///
/// Never encode meaning in color alone: a hotspot point's status is additionally carried by
/// `Charts`' categorical `.symbol(by:)` (a distinct marker shape) and restated as text in the
/// ranked hotspot list and each point's accessibility value — never color alone.
struct HotspotChartView: View {
    let diagram: GeneratedDiagram
    let codebase: Codebase

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @StateObject private var viewModel: HotspotViewModel
    @State private var showSidebar = false
    @State private var fullHistoryPhase: AsyncOperationPhase = .idle
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    init(diagram: GeneratedDiagram, artifact: CodeArtifact, codebase: Codebase) {
        self.diagram = diagram
        self.codebase = codebase
        self._viewModel = StateObject(wrappedValue: HotspotViewModel(artifact: artifact))
    }

    private var isCompactWidth: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        sidebarPresentedContent
            .navigationTitle(diagram.name)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .task {
                await viewModel.load(codebase: codebase, gitRepositoriesDir: model.store.gitRepositoriesDir)
            }
    }

    @ViewBuilder
    private var sidebarPresentedContent: some View {
        #if os(iOS)
        if isCompactWidth {
            chartContent
                .sheet(isPresented: $showSidebar) {
                    NavigationStack {
                        legendContent
                            .navigationTitle(.app("View.HotspotChartView.Hotspots"))
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button(.app("View.HotspotChartView.Done")) { showSidebar = false }
                                        .accessibilityIdentifier("diagram.sidebarDoneButton")
                                }
                            }
                    }
                }
        } else {
            chartContent
                .inspector(isPresented: $showSidebar) {
                    legendContent.inspectorColumnWidth(min: 260, ideal: 320, max: 420)
                }
        }
        #else
        chartContent
            .inspector(isPresented: $showSidebar) {
                legendContent.inspectorColumnWidth(min: 260, ideal: 320, max: 420)
            }
        #endif
    }

    // MARK: - Chart

    @ViewBuilder
    private var chartContent: some View {
        if viewModel.isLoading {
            loadingState
        } else if let message = viewModel.loadError {
            statusState(
                identifier: "hotspot.error",
                systemImage: "exclamationmark.triangle",
                text: .app("View.HotspotChartView.CouldNotLoadGitHistory \(message)"))
        } else if viewModel.isHistoryNotFetched {
            historyNotFetchedState
        } else if !viewModel.hasGitHistory {
            statusState(
                identifier: "hotspot.noGitHistory",
                systemImage: "questionmark.folder",
                text: .app("View.HotspotChartView.NoGitHistory")
            )
        } else if let hotspots = viewModel.hotspots, !hotspots.files.isEmpty {
            chart(hotspots)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("hotspot.chart")
        } else {
            statusState(
                identifier: "hotspot.noFilesToPlot", systemImage: "flame",
                text: .app("View.HotspotChartView.NoFilesToPlot")
            )
        }
    }

    /// Only an app-managed clone offers to fetch more: deepening a local folder's own repository
    /// would change the user's checkout, which the app never does.
    private var historyNotFetchedState: some View {
        VStack(spacing: .spacingM) {
            Image(systemName: "clock.badge.exclamationmark").font(.system(size: 28)).foregroundStyle(.secondary)
            if codebase.managedCheckout != nil, let remoteURL = codebase.repository?.remoteURL {
                Text(.app("View.HotspotChartView.HistoryNotFetched"))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                FetchFullHistoryButton(
                    remoteURL: remoteURL, phase: $fullHistoryPhase, identifierPrefix: "hotspot.fullHistory"
                ) {
                    Task {
                        await viewModel.load(codebase: codebase, gitRepositoriesDir: model.store.gitRepositoriesDir)
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text(.app("View.HotspotChartView.LocalHistoryShallow"))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.spacingXL)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hotspot.historyNotFetched")
    }

    private var loadingState: some View {
        VStack(spacing: .spacingM) {
            ProgressView()
            Text(.app("View.HotspotChartView.WalkingCommitHistory")).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("hotspot.loading")
    }

    private func statusState(identifier: String, systemImage: String, text: LocalizedStringResource) -> some View {
        VStack(spacing: .spacingM) {
            Image(systemName: systemImage).font(.system(size: 28)).foregroundStyle(.secondary)
            Text(localized: text).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.spacingXL)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(identifier)
    }

    private func chart(_ hotspots: Hotspots) -> some View {
        Chart {
            RuleMark(x: .value("Median churn", hotspots.churnThreshold))
                .foregroundStyle(.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            RuleMark(y: .value("Median complexity", hotspots.complexityThreshold))
                .foregroundStyle(.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            ForEach(hotspots.files) { file in
                filePointMark(file)
            }
        }
        .chartXAxisLabel { Text(.app("View.HotspotChartView.ChurnAxis")) }
        .chartYAxisLabel { Text(.app("View.HotspotChartView.ComplexityAxis")) }
        .chartForegroundStyleScale(["Hotspot": Color.red, "Normal": Color.blue])
        .chartSymbolScale(["Hotspot": BasicChartSymbolShape.diamond, "Normal": BasicChartSymbolShape.circle])
        .chartLegend(position: .bottom)
    }

    /// Split out of `chart`'s `ForEach` body to keep the chained-modifier expression small enough
    /// for the type checker (see `ModuleCouplingChartView.modulePointMark`'s identical rationale).
    private func filePointMark(_ file: Hotspots.File) -> some ChartContent {
        let category = file.isHotspot ? "Hotspot" : "Normal"
        let accessibilityText = "\(file.fileName): churn \(file.churn), complexity \(file.complexity)"
            + (file.isHotspot ? ", hotspot." : ".")
        return PointMark(
            x: .value("Churn", file.churn),
            y: .value("Complexity", file.complexity)
        )
        .symbol(by: .value("Status", category))
        .foregroundStyle(by: .value("Status", category))
        .symbolSize(file.isHotspot ? 130 : 60)
        .accessibilityLabel(file.fileName)
        .accessibilityValue(accessibilityText)
    }

    // MARK: - Legend / sidebar

    private var legendContent: some View {
        Group {
            if let hotspots = viewModel.hotspots {
                if hotspots.ranked.isEmpty {
                    Text(.app("View.HotspotChartView.NoFilesFallHotspot"))
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    List(hotspots.ranked) { file in
                        VStack(alignment: .leading, spacing: .spacingXS) {
                            HStack {
                                Image(systemName: "flame.fill")
                                Text(verbatim: file.fileName).font(.callout.bold())
                            }
                            Text(.app("View.HotspotChartView.ChurnComplexity \(file.churn) \(file.complexity)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    #if os(macOS)
                    .listStyle(.inset)
                    #endif
                }
            } else {
                Text(.app("View.HotspotChartView.NoDataYet")).foregroundStyle(.secondary).padding()
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                showSidebar.toggle()
            } label: {
                Label(.app("View.HotspotChartView.Sidebar"), systemImage: "sidebar.trailing")
            }
            .help(.app("View.HotspotChartView.ToggleRankedHotspotList"))
            .accessibilityIdentifier("diagram.sidebarToggleButton")
        }
    }
}
