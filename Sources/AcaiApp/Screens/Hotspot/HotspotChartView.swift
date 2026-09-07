import Charts
import SwiftUI
import AcaiCore

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
            .userActivity(DiagramHandoffActivity.activityType) {
                DiagramHandoffActivity(diagram: diagram, codebase: codebase).configure($0)
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
                systemImage: "exclamationmark.triangle",
                text: .app("View.HotspotChartView.CouldNotLoadGitHistory \(message)"))
        } else if !viewModel.hasGitHistory {
            statusState(
                systemImage: "questionmark.folder",
                text: .app("View.HotspotChartView.NoGitHistory")
            )
        } else if let data = viewModel.chartData, !data.points.isEmpty {
            chart(data)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            statusState(systemImage: "flame", text: .app("View.HotspotChartView.NoFilesToPlot"))
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(.app("View.HotspotChartView.WalkingCommitHistory")).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusState(systemImage: String, text: LocalizedStringResource) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(.system(size: 28)).foregroundStyle(.secondary)
            Text(localized: text).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chart(_ data: HotspotChartData) -> some View {
        Chart {
            RuleMark(x: .value("Median churn", data.churnThreshold))
                .foregroundStyle(.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            RuleMark(y: .value("Median complexity", data.complexityThreshold))
                .foregroundStyle(.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            ForEach(data.points) { point in
                filePointMark(point)
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
    private func filePointMark(_ point: HotspotChartData.Point) -> some ChartContent {
        let category = point.isHotspot ? "Hotspot" : "Normal"
        let accessibilityText = "\(point.fileName): churn \(point.churn), complexity \(point.complexity)"
            + (point.isHotspot ? ", hotspot." : ".")
        return PointMark(
            x: .value("Churn", point.churn),
            y: .value("Complexity", point.complexity)
        )
        .symbol(by: .value("Status", category))
        .foregroundStyle(by: .value("Status", category))
        .symbolSize(point.isHotspot ? 130 : 60)
        .accessibilityLabel(point.fileName)
        .accessibilityValue(accessibilityText)
    }

    // MARK: - Legend / sidebar

    private var legendContent: some View {
        Group {
            if let data = viewModel.chartData {
                if data.hotspots.isEmpty {
                    Text(.app("View.HotspotChartView.NoFilesFallHotspot"))
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    List(data.hotspots) { point in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "flame.fill")
                                Text(verbatim: point.fileName).font(.callout.bold())
                            }
                            Text(.app("View.HotspotChartView.ChurnComplexity \(point.churn) \(point.complexity)"))
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
