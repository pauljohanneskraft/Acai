import Testing
import AcaiCore

/// The union semantics behind the physical lines-of-code metric (#330): a nested type sits inside its
/// parent's extent and extension members sit outside the type's own, so the count is a union of line
/// ranges per file rather than a sum of spans.
@Suite("Lines of code")
struct LinesOfCodeTests {

    private func location(_ file: String, _ line: Int, _ endLine: Int?) -> AcaiCore.SourceLocation {
        AcaiCore.SourceLocation(filePath: file, line: line, column: 1, endLine: endLine)
    }

    private func method(_ name: String, at location: AcaiCore.SourceLocation) -> Member {
        Member(name: name, kind: .method, accessLevel: .internal, location: location)
    }

    @Test func spanCountsBothEndpoints() {
        #expect(location("A.swift", 10, 12).lineSpan == 3)
        #expect(location("A.swift", 10, 10).lineSpan == 1)
        #expect(location("A.swift", 10, nil).lineSpan == nil)
    }

    /// An `endLine` before the start line cannot report a negative span.
    @Test func invertedSpanReportsASingleLine() {
        #expect(location("A.swift", 10, 4).lineSpan == 1)
    }

    @Test func membersInsideTheDeclarationAreNotAddedTwice() {
        let type = TypeDeclaration(
            id: "Box", name: "Box", qualifiedName: "Box", kind: .struct, accessLevel: .internal,
            members: [method("area", at: location("Box.swift", 3, 5))],
            location: location("Box.swift", 1, 10))
        #expect(type.linesOfCode == 10)
    }

    /// Extension members are merged into the type they augment, so a type whose behaviour lives in
    /// another file is credited with those lines on top of its own declaration's.
    @Test func membersInAnotherFileAddTheirOwnLines() {
        let type = TypeDeclaration(
            id: "Box", name: "Box", qualifiedName: "Box", kind: .struct, accessLevel: .internal,
            members: [method("area", at: location("Box+Geometry.swift", 4, 7))],
            location: location("Box.swift", 1, 3))
        #expect(type.linesOfCode == 7)
    }

    @Test func anOverlappingMemberOnlyAddsItsLinesBeyondTheType() {
        let type = TypeDeclaration(
            id: "Box", name: "Box", qualifiedName: "Box", kind: .struct, accessLevel: .internal,
            members: [method("area", at: location("Box.swift", 8, 14))],
            location: location("Box.swift", 1, 10))
        #expect(type.linesOfCode == 14)
    }

    @Test func aNestedTypeInsideItsParentIsCountedOnce() {
        let nested = TypeDeclaration(
            id: "Box.Corner", name: "Corner", qualifiedName: "Box.Corner", kind: .struct,
            accessLevel: .internal, location: location("Box.swift", 4, 6))
        let type = TypeDeclaration(
            id: "Box", name: "Box", qualifiedName: "Box", kind: .struct, accessLevel: .internal,
            nestedTypes: [nested], location: location("Box.swift", 1, 10))
        #expect(type.linesOfCode == 10)
        #expect(nested.linesOfCode == 3)
    }

    @Test func aDeclarationWithNoEndLineIsNotMeasured() {
        let type = TypeDeclaration(
            id: "Box", name: "Box", qualifiedName: "Box", kind: .struct, accessLevel: .internal,
            location: location("Box.swift", 1, nil))
        #expect(type.linesOfCode == 0)
    }

    @Test func theCodebaseTotalCoversFreeFunctionsToo() {
        let first = TypeDeclaration(
            id: "Box", name: "Box", qualifiedName: "Box", kind: .struct, accessLevel: .internal,
            location: location("Box.swift", 1, 10))
        let second = TypeDeclaration(
            id: "Crate", name: "Crate", qualifiedName: "Crate", kind: .struct, accessLevel: .internal,
            location: location("Crate.swift", 1, 4))
        let metrics = CodeArtifact(
            metadata: .init(sourceLanguage: CodeArtifact.SourceLanguage(rawValue: "swift")),
            types: [first, second],
            freestandingFunctions: [method("pack", at: location("Crate.swift", 6, 8))]
        ).computeMetrics()
        #expect(metrics.counts.linesOfCode == 17)
        #expect(metrics.types.first { $0.name == "Box" }?.linesOfCode == 10)
        #expect(metrics.types.first { $0.name == "Crate" }?.linesOfCode == 4)
    }

    /// A union is order-independent, so the total cannot depend on which file the walk reached first.
    @Test func overlappingRangesMergeRegardlessOfInsertionOrder() {
        var ascending = LineSpanUnion()
        ascending.add(location("A.swift", 1, 5))
        ascending.add(location("A.swift", 4, 9))
        var descending = LineSpanUnion()
        descending.add(location("A.swift", 4, 9))
        descending.add(location("A.swift", 1, 5))
        #expect(ascending.lineCount == 9)
        #expect(descending.lineCount == 9)
    }

    /// A range fully inside one already recorded adds nothing, even when it arrives last.
    @Test func aContainedRangeAddsNothing() {
        var union = LineSpanUnion()
        union.add(location("A.swift", 1, 20))
        union.add(location("A.swift", 5, 8))
        #expect(union.lineCount == 20)
    }

    /// A cross-module extension's members are merged into the type they augment, so the type's own
    /// count spans both files — but the module row must be credited only with the lines written in its
    /// own files, the same attribution the coupling numbers beside it already use.
    ///
    /// `Beta` gets no row at all here: module rows are keyed on the modules that *declare* types, so a
    /// module holding nothing but extensions has never had one. Its lines still reach the codebase
    /// total, which is why that total can exceed the sum of the module rows.
    @Test func moduleTotalsFollowTheFileNotTheTypesModule() {
        let type = TypeDeclaration(
            id: "Box", name: "Box", qualifiedName: "Box", kind: .struct, accessLevel: .public,
            members: [method("area", at: location("Sources/Beta/Box+Geometry.swift", 1, 4))],
            location: location("Sources/Alpha/Box.swift", 1, 6))
        let metrics = CodeArtifact(
            metadata: .init(sourceLanguage: CodeArtifact.SourceLanguage(rawValue: "swift")),
            types: [type]
        ).computeMetrics()
        #expect(metrics.types.first?.linesOfCode == 10)
        #expect(metrics.counts.linesOfCode == 10)
        #expect(metrics.modules.first { $0.name == "Alpha" }?.linesOfCode == 6)
        #expect(metrics.modules.contains { $0.name == "Beta" } == false)
    }

    @Test func linesAreAttributedToTheFileTheyWereWrittenIn() {
        var union = LineSpanUnion()
        union.add(location("Sources/Alpha/Box.swift", 1, 10))
        union.add(location("Sources/Beta/Crate.swift", 1, 4))
        #expect(union.lineCount == 14)
        let byModule = union.lineCounts(groupedBy: { ModuleResolver.standard.productName(forFilePath: $0) })
        #expect(byModule == ["Alpha": 10, "Beta": 4])
    }
}
