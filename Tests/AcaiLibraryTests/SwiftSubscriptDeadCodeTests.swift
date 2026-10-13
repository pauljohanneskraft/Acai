import Testing
import AcaiCore
import AcaiDiagram
@testable import AcaiLibrary

@Suite("Swift initializer and subscript dead-code scan")
struct SwiftSubscriptDeadCodeTests {
    @Test func aCalledSwiftInitializerIsNotReportedWhileAnUncalledOneIs() {
        let artifact = SwiftCodeParser().parse(source: """
        class Called { init() {} }
        class Uncalled { init() {} }
        class Worker {
            public func use() { _ = Called() }
        }
        """, fileName: "Thing.swift")
        let report = DeadCodeScan(
            artifact: artifact, languages: artifact.standardLanguageResolver).report
        #expect(report.candidates.map(\.id) == ["Uncalled.init"])
    }

    /// Opting `.initializer` and `.subscript` in doesn't relax the method scan.
    @Test func anUnusedMethodIsStillReportedAlongsideTheNewKinds() {
        let artifact = SwiftCodeParser().parse(source: """
        class Thing {
            init(unused: Int) {}
            subscript(i: Int) -> Int { 0 }
            private func unusedMethod() {}
        }
        """, fileName: "Thing.swift")
        let report = DeadCodeScan(
            artifact: artifact, languages: artifact.standardLanguageResolver).report
        #expect(report.candidates.map(\.id).sorted() == ["Thing.init", "Thing.subscript", "Thing.unusedMethod"])
    }

    @Test func aCalledSwiftSubscriptIsNotReportedWhileAnUncalledOneIs() {
        let artifact = SwiftCodeParser().parse(source: """
        class Called { subscript(i: Int) -> Int { 0 } }
        class Uncalled { subscript(i: Int) -> Int { 0 } }
        class Worker {
            let called = Called()
            public func use() { _ = called[0] }
        }
        """, fileName: "Thing.swift")
        let report = DeadCodeScan(
            artifact: artifact, languages: artifact.standardLanguageResolver).report
        #expect(report.candidates.map(\.id) == ["Uncalled.subscript"])
    }

    @Test func aSwiftSubscriptCalledOnlyFromAnotherFileIsNotReported() {
        let matrix = SwiftCodeParser().parse(source: """
        struct Matrix { subscript(i: Int) -> Int { i } }
        """, fileName: "Matrix.swift")
        let user = SwiftCodeParser().parse(source: """
        struct User {
            let matrix: Matrix
            public func use() -> Int { matrix[0] }
        }
        """, fileName: "User.swift")
        let artifact = matrix.merging(with: user).resolvingCallSiteReceivers()
        let report = DeadCodeScan(
            artifact: artifact, languages: artifact.standardLanguageResolver).report
        #expect(!report.candidates.map(\.id).contains("Matrix.subscript"))
    }

    @Test func aSubscriptOnATypeOutsideTheProjectLeavesCoverageAlone() {
        let artifact = SwiftCodeParser().parse(source: """
        import SwiftyJSON
        struct User {
            let payload: JSON
            func name() -> JSON { payload["name"] }
        }
        """, fileName: "User.swift").resolvingCallSiteReceivers()
        let graph = CallGraphBuilder().build(from: artifact)
        #expect(graph.coverage.total == 0)
    }
}
