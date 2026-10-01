import Testing
import AcaiCore
import AcaiDiagram
@testable import AcaiLibrary

/// `LanguageConfiguration.deadCodeMemberKinds` is only sound while each language's claim matches what
/// its parser records: a kind whose callers are never recorded has no edge to be found by, so scanning
/// it would report every declaration of it as uncalled. These tests pin both halves — the claim, and
/// the parser behaviour it rests on — so an opt-in has to be a deliberate change to both.
@Suite("Dead-code member-kind audit")
struct DeadCodeMemberKindAuditTests {

    @Test(arguments: AnalysisService.standardParsers.map(\.language).filter { $0 != .swift })
    func everyOtherBuiltInLanguageScansMethodsOnly(language: CodeArtifact.SourceLanguage) throws {
        let parser = try #require(AnalysisService.standardParsers.first { $0.language == language })
        #expect(parser.configuration.deadCodeMemberKinds == [.method])
    }

    /// Swift is the one built-in language whose parser records a caller edge for both `Thing()` and a
    /// same-file-typed subscript access (issue #412), so it alone opts `.initializer`/`.subscript` in.
    @Test func swiftScansMethodsInitializersAndSubscripts() throws {
        let parser = try #require(AnalysisService.standardParsers.first { $0.language == .swift })
        #expect(parser.configuration.deadCodeMemberKinds == [.method, .initializer, .subscript])
    }

    private func callSites(_ source: String, in memberName: String, of parser: any CodeParser,
                           fileName: String) throws -> [CallSite] {
        let artifact = parser.parse(source: source, fileName: fileName)
        let member = try #require(
            artifact.flattened().flatMap(\.members).first { $0.name == memberName })
        return member.callSites
    }

    private func memberKinds(_ source: String, of parser: any CodeParser,
                             fileName: String) throws -> [String: MemberKind] {
        let members = parser.parse(source: source, fileName: fileName).flattened().flatMap(\.members)
        try #require(!members.isEmpty)
        return Dictionary(members.map { ($0.name, $0.kind) }) { first, _ in first }
    }

    /// Why Swift opts `.initializer` in: both the dominant `Thing()` spelling and the explicit
    /// `Thing.init(…)` form now leave a caller edge behind.
    @Test func swiftRecordsBothAConstructionAndAnExplicitInitCall() throws {
        let sites = try callSites("""
        class Thing {
            init() {}
            init(x: Int) {}
            func use() {
                let made = Thing()
                _ = Thing.init(x: 1)
                _ = made
            }
        }
        """, in: "use", of: SwiftCodeParser(), fileName: "Thing.swift")

        #expect(sites.map(\.methodName) == ["init", "init"])
        #expect(sites.map(\.receiver) == [.type("Thing"), .type("Thing")])
    }

    /// Why Swift opts `.subscript` in: a subscript access on a same-file declared type now leaves a
    /// caller edge behind, in both its `self` and property/local-receiver forms.
    @Test func swiftRecordsSubscriptAccessOnALocallyDeclaredType() throws {
        let sites = try callSites("""
        class Thing {
            subscript(i: Int) -> Int { 0 }
            func use() {
                let made = Thing()
                _ = made[0]
                _ = self[1]
            }
        }
        """, in: "use", of: SwiftCodeParser(), fileName: "Thing.swift")

        let subscriptSites = sites.filter { $0.methodName == "subscript" }
        #expect(subscriptSites.count == 2)
        #expect(subscriptSites.contains { $0.receiver == .type("Thing") })
        #expect(subscriptSites.contains { $0.receiver == .selfDispatch })
    }

    /// Why the tree-sitter languages decline `.initializer`: a construction reaches the shared
    /// `CallSiteScope.bareCall`, which drops a callee that names a known type.
    @Test func kotlinRecordsNoConstructorCall() throws {
        let sites = try callSites("""
        class Thing(val x: Int) {
            constructor() : this(0) {}
            fun use() {
                val made = Thing(1)
                val empty = Thing()
            }
        }
        """, in: "use", of: KotlinCodeParser(), fileName: "Thing.kt")

        #expect(sites.isEmpty)
    }

    @Test func kotlinExtractsAnOperatorGetAsAMethod() throws {
        let kinds = try memberKinds("""
        class Grid {
            operator fun get(i: Int): Int = i
        }
        """, of: KotlinCodeParser(), fileName: "Grid.kt")
        #expect(kinds["get"] == .method)
    }

    @Test func javaRecordsNoConstructorCall() throws {
        let sites = try callSites("""
        class Thing {
            Thing() {}
            Thing(int x) {}
            void use() {
                Thing made = new Thing();
                Thing other = new Thing(1);
            }
        }
        """, in: "use", of: JavaCodeParser(), fileName: "Thing.java")

        #expect(sites.isEmpty)
    }

    @Test(arguments: [true, false])
    func jsRecordsNoConstructorCall(isTypeScript: Bool) throws {
        let sites = try callSites("""
        class Thing {
            constructor(x) {}
            use() {
                const made = new Thing(1);
            }
        }
        """, in: "use", of: JSCodeParser(isTypeScript: isTypeScript),
           fileName: isTypeScript ? "Thing.ts" : "Thing.js")

        #expect(sites.isEmpty)
    }

    @Test func dartRecordsNoConstructorCall() throws {
        let sites = try callSites("""
        class Thing {
          Thing();
          Thing.named();
          void use() {
            final made = Thing();
            final other = Thing.named();
          }
        }
        """, in: "use", of: DartCodeParser(), fileName: "thing.dart")

        #expect(sites.isEmpty)
    }

    @Test func dartExtractsAnIndexOperatorAsAMethod() throws {
        let kinds = try memberKinds("""
        class Grid {
          int operator [](int i) => i;
        }
        """, of: DartCodeParser(), fileName: "grid.dart")
        #expect(kinds.values.contains(.method))
        #expect(!kinds.values.contains(.subscript))
    }

    /// Why Python declines `.initializer`: a construction is recorded, but as a free call named after
    /// the class, which no `Thing.__init__` edge can come from.
    @Test func pythonRecordsAConstructionAsAFreeCallNamedAfterTheClass() throws {
        let sites = try callSites("""
        class Thing:
            def __init__(self):
                pass

            def use(self):
                made = Thing()
        """, in: "use", of: PythonCodeParser(), fileName: "thing.py")

        #expect(sites.map(\.receiver) == [.free])
        #expect(sites.map(\.methodName) == ["Thing"])
    }

    @Test func pythonExtractsGetItemAsAMethod() throws {
        let kinds = try memberKinds("""
        class Grid:
            def __getitem__(self, i):
                return i
        """, of: PythonCodeParser(), fileName: "grid.py")
        #expect(kinds["__getitem__"] == .method)
    }

    @Test func cppRecordsNoConstructorCall() throws {
        let sites = try callSites("""
        class Thing {
        public:
            Thing() {}
            Thing(int x) {}
            void use() {
                Thing made;
                Thing other(1);
            }
        };
        """, in: "use", of: CppCodeParser(), fileName: "Thing.cpp")

        #expect(sites.isEmpty)
    }

    @Test func cppExtractsAnIndexOperatorAsAMethod() throws {
        let kinds = try memberKinds("""
        class Grid {
        public:
            int operator[](int i) { return i; }
        };
        """, of: CppCodeParser(), fileName: "Grid.cpp")
        #expect(kinds.values.contains(.method))
        #expect(!kinds.values.contains(.subscript))
    }

    /// Why C declines both: the language has neither construct, so neither kind can be declared at all.
    /// Everything callable in C reaches the scan as a method — a `struct`'s function-pointer field is
    /// extracted as one, and C's own functions are freestanding methods.
    @Test func cDeclaresNoInitializerOrSubscriptMember() throws {
        let artifact = CCodeParser().parse(source: """
        struct Grid {
            int size;
            int (*resize)(int);
        };

        int grid_resize(struct Grid *g, int n) { return n; }
        """, fileName: "grid.c")

        let members = artifact.flattened().flatMap(\.members)
        try #require(!members.isEmpty)
        let kinds = Dictionary(members.map { ($0.name, $0.kind) }) { first, _ in first }
        #expect(kinds["size"] == .property)
        #expect(kinds["resize"] == .method)
        #expect(!members.contains { $0.kind == .initializer || $0.kind == .subscript })
        #expect(artifact.freestandingFunctions.filter { $0.name == "grid_resize" }.map(\.kind) == [.method])
    }

    /// The end-to-end consequence, through the real registry rather than a fixture configuration: a
    /// called Swift initializer is not reported, while an uncalled one (on an otherwise identical
    /// sibling type) still is — same bar #343 set for methods, now met for `.initializer`.
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

    /// The `.subscript` analogue: a called subscript is not reported, while an uncalled one on a
    /// sibling type still is.
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

    /// A method is still reported alongside the new kinds — opting `.initializer`/`.subscript` in
    /// doesn't relax the existing method scan.
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
}
