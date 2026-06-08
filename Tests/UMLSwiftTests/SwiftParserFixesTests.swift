import Testing
@testable import UMLSwift
@testable import UMLCore

/// Regression tests for the parse-time fixes (BUG-0/4/5/8/9/10 and GAP-1/4/5/6/11/12).
@Suite("Swift: Parser Fixes")
struct SwiftParserFixesTests {
    let parser = SwiftCodeParser()

    // MARK: BUG-0 — nested functions/initializers must not drop declarations

    @Test func nestedFunctionDoesNotDropEnclosingOrSiblingTypes() {
        let source = """
        struct First {
            func outer() {
                func nested() {}
                _ = nested
            }
        }
        struct Second {}
        """
        let artifact = parser.parse(source: source, fileName: "F.swift")
        let names = artifact.types.map(\.name).sorted()
        #expect(names == ["First", "Second"])
        let first = artifact.types.first { $0.name == "First" }
        // The nested function must NOT be recorded as a member; only `outer` is.
        #expect(first?.members.filter { $0.kind == .method }.map(\.name) == ["outer"])
    }

    @Test func nestedFunctionInInitializerDoesNotCorruptParsing() {
        let source = """
        struct A {
            init() {
                func helper() {}
                helper()
            }
        }
        enum B { case x }
        """
        let artifact = parser.parse(source: source, fileName: "A.swift")
        #expect(artifact.types.map(\.name).sorted() == ["A", "B"])
        let a = artifact.types.first { $0.name == "A" }
        #expect(a?.members.contains { $0.kind == .initializer } == true)
        #expect(a?.members.contains { $0.kind == .method } == false)
    }

    // MARK: BUG-4 — attributes must not leak into inheritance/conformance targets

    @Test func attributedConformanceStripsAttribute() {
        let source = "final class Box: @unchecked Sendable {}"
        let artifact = parser.parse(source: source, fileName: "Box.swift")
        let targets = artifact.relationships.map(\.target)
        #expect(targets.contains("Sendable"))
        #expect(!targets.contains { $0.contains("@") })
        #expect(artifact.types[0].inheritedTypes.map(\.name) == ["Sendable"])
    }

    // MARK: BUG-5 / GAP-2 — private(set) access

    @Test func baredPrivateSetReportsInternalGetterAndPrivateSetter() {
        let source = """
        struct Counter {
            private(set) var count = 0
            public private(set) var name = ""
        }
        """
        let artifact = parser.parse(source: source, fileName: "Counter.swift")
        let members = artifact.types[0].members
        let count = members.first { $0.name == "count" }
        #expect(count?.accessLevel == .internal)
        #expect(count?.setAccessLevel == .private)
        let name = members.first { $0.name == "name" }
        #expect(name?.accessLevel == .public)
        #expect(name?.setAccessLevel == .private)
    }

    // MARK: BUG-8 — #if must not double-count declarations

    @Test func conditionalCompilationDoesNotDuplicateTypes() {
        let source = """
        #if os(iOS)
        struct Widget { var a: Int }
        #else
        struct Widget { var b: Int }
        #endif
        """
        let artifact = parser.parse(source: source, fileName: "Widget.swift")
        #expect(artifact.types.filter { $0.name == "Widget" }.count == 1)
    }

    // MARK: BUG-9 — multi-binding type propagation

    @Test func multiBindingInheritsTrailingTypeAnnotation() {
        let source = """
        struct Point {
            let x, y: Double
        }
        """
        let artifact = parser.parse(source: source, fileName: "Point.swift")
        let members = artifact.types[0].members
        #expect(members.count == 2)
        #expect(members.allSatisfy { $0.type?.name == "Double" })
    }

    // MARK: BUG-10 — tuple-pattern stored properties

    @Test func tuplePatternProducesOneMemberPerElement() {
        let source = """
        struct Pair {
            let (first, second): (Int, String) = (0, "")
        }
        """
        let artifact = parser.parse(source: source, fileName: "Pair.swift")
        let members = artifact.types[0].members
        #expect(members.map(\.name) == ["first", "second"])
        #expect(members.first { $0.name == "first" }?.type?.name == "Int")
        #expect(members.first { $0.name == "second" }?.type?.name == "String")
    }

    // MARK: GAP-1 — global variables/constants

    @Test func topLevelLetAndVarCapturedAsGlobals() {
        let source = """
        let maxCount = 10
        var current = 0
        struct Thing {}
        """
        let artifact = parser.parse(source: source, fileName: "G.swift")
        #expect(artifact.globalVariables.map(\.name).sorted() == ["current", "maxCount"])
        // Globals are not confused with type members.
        #expect(artifact.types.map(\.name) == ["Thing"])
    }

    // MARK: GAP-3 — actor kind

    @Test func actorHasActorKind() {
        let artifact = parser.parse(source: "actor Store {}", fileName: "S.swift")
        #expect(artifact.types[0].kind == .actor)
        #expect(!artifact.types[0].annotations.contains("@actor"))
    }

    // MARK: GAP-4 — associatedtype + primary associated types

    @Test func protocolAssociatedTypesCaptured() {
        let source = """
        protocol Container<Item> {
            associatedtype Iterator
            var first: Item { get }
        }
        """
        let artifact = parser.parse(source: source, fileName: "C.swift")
        let proto = artifact.types[0]
        #expect(proto.genericParameters.map(\.name) == ["Item"])
        #expect(proto.associatedTypes.map(\.name) == ["Iterator"])
    }

    // MARK: GAP-5 — where-clause constraints populate .sameType

    @Test func whereClauseSameTypeConstraintCaptured() {
        let source = """
        struct Wrapper<T> where T == Int {
            var value: T
        }
        """
        let artifact = parser.parse(source: source, fileName: "W.swift")
        let constraints = artifact.types[0].genericParameters.flatMap(\.constraints)
        #expect(constraints.contains { $0.kind == .sameType && $0.type.name == "Int" })
    }

    // MARK: GAP-6 — attribute arguments preserved

    @Test func attributeArgumentsArePreserved() {
        let source = """
        @available(iOS 15, *)
        struct Modern {}
        """
        let artifact = parser.parse(source: source, fileName: "M.swift")
        #expect(artifact.types[0].annotations.contains { $0.hasPrefix("@available") && $0.contains("iOS 15") })
    }

    // MARK: GAP-11 — Array<T> / Optional<T> normalization

    @Test func genericSugarSpellingsAreNormalized() {
        let source = """
        struct Holder {
            var a: Array<Int>
            var b: Optional<String>
        }
        """
        let artifact = parser.parse(source: source, fileName: "H.swift")
        let members = artifact.types[0].members
        let arr = members.first { $0.name == "a" }
        #expect(arr?.type?.isArray == true)
        let opt = members.first { $0.name == "b" }
        #expect(opt?.type?.isOptional == true)
        #expect(opt?.type?.name == "String")
    }

    // MARK: GAP-12 — parse errors surfaced

    @Test func malformedSourceFlagsParseErrors() {
        let good = parser.parse(source: "struct Ok {}", fileName: "Ok.swift")
        #expect(good.metadata.hasParseErrors == false)
        let bad = parser.parse(source: "struct Broken { func (", fileName: "Bad.swift")
        #expect(bad.metadata.hasParseErrors == true)
    }
}
