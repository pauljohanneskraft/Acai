import Charts
import SwiftUI
import AcaiCore

/// Read-only analysis view: every module plotted as a point on an Abstractness-vs-
/// Instability chart, with Robert Martin's main-sequence line (`A + I = 1`) drawn across it. Not a
/// movement canvas (no drag/undo/redo/Save-as-Freeform/Export — see `GeneratedDiagram+Freeform.swift`'s
/// doc comment on why) — this is a chart over already-computed metrics, built once and never
/// recomputed on every render.
///
/// Never encode meaning in color alone: each point's zone is additionally carried
/// by `Charts`' categorical `.symbol(by:)` (a distinct marker shape per zone) and restated as text
/// in the ranked legend list and in each point's accessibility value.
struct ModuleCouplingChartView: View {
    let diagram: GeneratedDiagram
    let codebase: Codebase
    private let data: ModuleCouplingChartData

    @State private var showSidebar = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    init(diagram: GeneratedDiagram, artifact: CodeArtifact, codebase: Codebase) {
        self.diagram = diagram
        self.codebase = codebase
        self.data = ModuleCouplingChartData(modules: artifact.computeMetrics().modules)
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
                        legendList
                            .navigationTitle(.app("View.ModuleCouplingChartView.Modules"))
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button(.app("View.ModuleCouplingChartView.Done")) { showSidebar = false }
                                        .accessibilityIdentifier("diagram.sidebarDoneButton")
                                }
                            }
                    }
                }
        } else {
            chartContent
                .inspector(isPresented: $showSidebar) {
                    legendList.inspectorColumnWidth(min: 240, ideal: 300, max: 380)
                }
        }
        #else
        chartContent
            .inspector(isPresented: $showSidebar) {
                legendList.inspectorColumnWidth(min: 240, ideal: 300, max: 380)
            }
        #endif
    }

    // MARK: - Chart

    private var chartContent: some View {
        Group {
            if data.points.isEmpty {
                emptyState
            } else {
                chart
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line").font(.system(size: 28)).foregroundStyle(.secondary)
            Text(.app("View.ModuleCouplingChartView.NoModulesPlotYet"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chart: some View {
        Chart {
            ForEach(mainSequenceLine, id: \.self.instability) { point in
                LineMark(
                    x: .value("Instability", point.instability),
                    y: .value("Abstractness", point.abstractness)
                )
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .interpolationMethod(.linear)
            }
            ForEach(data.points) { point in
                modulePointMark(point)
            }
        }
        .chartXScale(domain: 0...1)
        .chartYScale(domain: 0...1)
        .chartXAxisLabel { Text(.app("View.ModuleCouplingChartView.InstabilityAxis")) }
        .chartYAxisLabel { Text(.app("View.ModuleCouplingChartView.AbstractnessAxis")) }
        .chartForegroundStyleScale([
            ModuleCouplingChartData.Zone.painful.rawValue: Color.red,
            ModuleCouplingChartData.Zone.useless.rawValue: Color.orange,
            ModuleCouplingChartData.Zone.balanced.rawValue: Color.green
        ])
        .chartSymbolScale([
            ModuleCouplingChartData.Zone.painful.rawValue: BasicChartSymbolShape.triangle,
            ModuleCouplingChartData.Zone.useless.rawValue: BasicChartSymbolShape.square,
            ModuleCouplingChartData.Zone.balanced.rawValue: BasicChartSymbolShape.circle
        ])
        .chartLegend(position: .bottom)
    }

    /// Split out of `chart`'s `ForEach` body — chaining every modifier inline made the containing
    /// expression too large for the type checker to solve in reasonable time.
    private func modulePointMark(_ point: ModuleCouplingChartData.Point) -> some ChartContent {
        let accessibilityText = "\(point.zone.rawValue). Instability \(percent(point.instability)), "
            + "abstractness \(percent(point.abstractness)), "
            + "distance from main sequence \(percent(point.distance))."
        return PointMark(
            x: .value("Instability", point.instability),
            y: .value("Abstractness", point.abstractness)
        )
        .symbol(by: .value("Zone", point.zone.rawValue))
        .foregroundStyle(by: .value("Zone", point.zone.rawValue))
        .symbolSize(symbolSize(for: point.distance))
        .accessibilityLabel(point.name)
        .accessibilityValue(accessibilityText)
    }

    /// Two endpoints are enough for `Charts` to draw the whole `A + I = 1` line.
    private var mainSequenceLine: [(instability: Double, abstractness: Double)] {
        [(0, 1), (1, 0)]
    }

    /// Bigger marker = farther from the main sequence — a second, size-based non-color signal
    /// alongside the shape/label ones.
    private func symbolSize(for distance: Double) -> Double {
        60 + distance * 140
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    // MARK: - Legend / sidebar

    private var legendList: some View {
        List(data.rankedByDistance) { point in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: point.zone.symbolName)
                    Text(verbatim: point.name).font(.callout.bold())
                    Spacer()
                    Text(verbatim: percent(point.distance)).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                let instability = percent(point.instability)
                let abstractness = percent(point.abstractness)
                Text(.app("View.ModuleCouplingChartView.Zone \(point.zone.rawValue) \(instability) \(abstractness)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
        #if os(macOS)
        .listStyle(.inset)
        #endif
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                showSidebar.toggle()
            } label: {
                Label(.app("View.ModuleCouplingChartView.Sidebar"), systemImage: "sidebar.trailing")
            }
            .help(.app("View.ModuleCouplingChartView.ToggleRankedModuleList"))
            .accessibilityIdentifier("diagram.sidebarToggleButton")
        }
    }
}
