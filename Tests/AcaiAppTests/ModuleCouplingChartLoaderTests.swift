import Foundation
import Testing
import AcaiCore
@testable import AcaiApp

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

/// Holds the first computation until `release()`, so a test can act while it is in flight.
private final class GatedMetrics: ModuleCouplingMetrics, @unchecked Sendable {
    let started: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation
    private let gate = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var calls = 0

    init() {
        (started, startedContinuation) = AsyncStream.makeStream()
    }

    func release() {
        gate.signal()
    }

    func chartData(of artifact: CodeArtifact) -> ModuleCouplingChartData {
        lock.lock()
        let isFirst = calls == 0
        calls += 1
        lock.unlock()
        if isFirst {
            startedContinuation.yield()
            gate.wait()
        }
        return ArtifactModuleCouplingMetrics().chartData(of: artifact)
    }
}

@Suite("Module Coupling chart loader", .timeLimit(.minutes(1)))
@MainActor
struct ModuleCouplingChartLoaderTests {

    private func artifact(module: String = "Core") -> CodeArtifact {
        let path = "Sources/\(module)/Foo.swift"
        return CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: [path]),
            types: [
                TypeDeclaration(
                    id: "Foo", name: "Foo", qualifiedName: "Foo", kind: .class, accessLevel: .public,
                    location: .init(filePath: path, line: 1, column: 1))
            ])
    }

    private func identity(revision: Int = 0, comparisonGitRef: String? = nil) -> ModuleCouplingChartIdentity {
        ModuleCouplingChartIdentity(
            analysis: ProjectBrowserViewModel.AnalysisToken(
                lastIndexed: Date(timeIntervalSince1970: 0), configuration: nil, revision: revision),
            comparisonBaseRef: nil,
            comparisonGitRef: comparisonGitRef,
            showsComparisonArtifact: comparisonGitRef != nil)
    }

    private func moduleIDs(of artifact: CodeArtifact) -> [String] {
        ArtifactModuleCouplingMetrics().chartData(of: artifact).points.map(\.id)
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

    @Test("The comparison revision arriving under unchanged refs recomputes")
    func loadedComparisonArtifactRecomputes() async {
        let metrics = CountingMetrics()
        let loader = ModuleCouplingChartLoader(metrics: metrics)
        let pending = ModuleCouplingChartIdentity(
            analysis: identity().analysis, comparisonBaseRef: nil, comparisonGitRef: "v1",
            showsComparisonArtifact: false)
        let loaded = ModuleCouplingChartIdentity(
            analysis: identity().analysis, comparisonBaseRef: nil, comparisonGitRef: "v1",
            showsComparisonArtifact: true)

        await loader.load(identity: pending, of: artifact())
        await loader.load(identity: loaded, of: artifact())

        #expect(metrics.computations == 2)
    }

    @Test("Re-requesting an analysis whose first request was cancelled mid-walk still delivers it")
    func cancelledRequestDoesNotStrandItsIdentity() async {
        let metrics = GatedMetrics()
        let loader = ModuleCouplingChartLoader(metrics: metrics)
        let shared = artifact()
        let sharedIdentity = identity()

        let first = Task { await loader.load(identity: sharedIdentity, of: shared) }
        var started = metrics.started.makeAsyncIterator()
        await started.next()
        first.cancel()
        async let second: Void = loader.load(identity: sharedIdentity, of: shared)
        metrics.release()
        await second
        await first.value

        #expect(loader.data != nil)
        #expect(!loader.isComputing)
    }

    @Test("A superseded walk's result never replaces the current analysis's chart")
    func supersededResultIsDiscarded() async {
        let metrics = GatedMetrics()
        let loader = ModuleCouplingChartLoader(metrics: metrics)
        let old = artifact(module: "Old")
        let new = artifact(module: "New")
        #expect(moduleIDs(of: old) != moduleIDs(of: new))

        let first = Task { await loader.load(identity: identity(revision: 1), of: old) }
        var started = metrics.started.makeAsyncIterator()
        await started.next()
        await loader.load(identity: identity(revision: 2), of: new)
        metrics.release()
        await first.value

        #expect(loader.data?.points.map(\.id) == moduleIDs(of: new))
        #expect(!loader.isComputing)
    }
}
