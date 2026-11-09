import Foundation
import Testing
import AcaiCore
@testable import AcaiApp

/// Counts how often the chart's metrics are actually computed. Injected into the loader under test
/// rather than held anywhere shared, so each test owns its own count.
private final class CountingMetrics: ModuleCouplingMetrics, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var computations: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func chartData(of artifact: CodeArtifact) -> ModuleCouplingChartData {
        lock.lock()
        count += 1
        lock.unlock()
        return ArtifactModuleCouplingMetrics().chartData(of: artifact)
    }
}

/// `ModuleCouplingChartView` is re-created on every parent update, so the walk behind its chart has
/// to be keyed on the analysis rather than on the view's lifetime.
@Suite("Module Coupling chart loader", .timeLimit(.minutes(1)))
@MainActor
struct ModuleCouplingChartLoaderTests {

    private func artifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Sources/Core/Foo.swift"]),
            types: [
                TypeDeclaration(
                    id: "Foo", name: "Foo", qualifiedName: "Foo", kind: .class, accessLevel: .public,
                    location: .init(filePath: "Sources/Core/Foo.swift", line: 1, column: 1))
            ])
    }

    private func identity(revision: Int = 0, comparisonGitRef: String? = nil) -> ModuleCouplingChartIdentity {
        ModuleCouplingChartIdentity(
            analysis: ProjectBrowserViewModel.AnalysisToken(
                lastIndexed: Date(timeIntervalSince1970: 0), configuration: nil, revision: revision),
            comparisonBaseRef: nil,
            comparisonGitRef: comparisonGitRef)
    }

    @Test("Building the chart twice for the same analysis computes its metrics once")
    func sameAnalysisComputesOnce() async {
        let metrics = CountingMetrics()
        let loader = ModuleCouplingChartLoader(metrics: metrics)

        await loader.load(identity: identity(), of: artifact())
        await loader.load(identity: identity(), of: artifact())

        #expect(metrics.computations == 1)
        #expect(loader.data != nil)
    }

    @Test("A new analysis recomputes")
    func changedAnalysisRecomputes() async {
        let metrics = CountingMetrics()
        let loader = ModuleCouplingChartLoader(metrics: metrics)

        await loader.load(identity: identity(revision: 1), of: artifact())
        await loader.load(identity: identity(revision: 2), of: artifact())

        #expect(metrics.computations == 2)
    }

    @Test("Two requests for the same analysis at once compute its metrics once")
    func concurrentRequestsComputeOnce() async {
        let metrics = CountingMetrics()
        let loader = ModuleCouplingChartLoader(metrics: metrics)
        let shared = artifact()
        let sharedIdentity = identity()

        async let first: Void = loader.load(identity: sharedIdentity, of: shared)
        async let second: Void = loader.load(identity: sharedIdentity, of: shared)
        _ = await (first, second)

        #expect(metrics.computations == 1)
    }

    @Test("A different comparison revision recomputes, although the analysis is the same")
    func changedComparisonRefRecomputes() async {
        let metrics = CountingMetrics()
        let loader = ModuleCouplingChartLoader(metrics: metrics)

        await loader.load(identity: identity(comparisonGitRef: "v1"), of: artifact())
        await loader.load(identity: identity(comparisonGitRef: "v2"), of: artifact())

        #expect(metrics.computations == 2)
    }

    @Test("The loader reports it is computing only while it is")
    func reportsComputingState() async {
        let loader = ModuleCouplingChartLoader(metrics: CountingMetrics())
        #expect(!loader.isComputing)

        await loader.load(identity: identity(), of: artifact())

        #expect(!loader.isComputing)
    }
}
