import Testing
import AcaiCore
import AcaiDiagram
@testable import AcaiLibrary

@Suite("Swift subscript dead-code scan")
struct SwiftSubscriptDeadCodeTests {
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
}
