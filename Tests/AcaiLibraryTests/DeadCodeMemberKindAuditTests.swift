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

    @Test(arguments: AnalysisService.standardParsers.map(\.language))
    func everyBuiltInLanguageScansMethodsOnly(language: CodeArtifact.SourceLanguage) throws {
        let parser = try #require(AnalysisService.standardParsers.first { $0.language == language })
        #expect(parser.configuration.deadCodeMemberKinds == [.method])
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

    /// Why Swift declines `.initializer`: the dominant `Thing()` spelling is read as a construction and
    /// dropped, so only the explicit `Thing.init(…)` form leaves an edge behind.
    @Test func swiftRecordsAnExplicitInitCallButNotAConstruction() throws {
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

        #expect(sites.map(\.methodName) == ["init"])
        #expect(sites.map(\.receiver) == [.type("Thing")])
    }

    /// Why Swift declines `.subscript`: a subscript access is not recorded at all, in any position.
    @Test func swiftRecordsNoSubscriptAccess() throws {
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

        #expect(sites.isEmpty)
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

    /// The end-to-end consequence, through the real registry rather than a fixture configuration: an
    /// uncalled Swift initializer and subscript are not reported, while an uncalled method still is.
    @Test func aSwiftInitializerAndSubscriptAreNotReportedWhileAMethodIs() {
        let artifact = SwiftCodeParser().parse(source: """
        class Thing {
            init(unused: Int) {}
            subscript(i: Int) -> Int { 0 }
            private func unusedMethod() {}
        }
        """, fileName: "Thing.swift")
        let report = DeadCodeScan(
            artifact: artifact, languages: artifact.standardLanguageResolver).report
        #expect(report.candidates.map(\.id) == ["Thing.unusedMethod"])
    }
}
