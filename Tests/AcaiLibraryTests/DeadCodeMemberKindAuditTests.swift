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

    /// Java, Kotlin and Dart now also scan `.initializer` — each has its own dedicated pair of tests
    /// below pinning the parser behaviour that justifies it. Every other built-in language still
    /// scans methods only.
    @Test(arguments: AnalysisService.standardParsers
        .map(\.language)
        .filter { $0 != .java && $0 != .kotlin && $0 != .dart })
    func everyOtherBuiltInLanguageScansMethodsOnly(language: CodeArtifact.SourceLanguage) throws {
        let parser = try #require(AnalysisService.standardParsers.first { $0.language == language })
        #expect(parser.configuration.deadCodeMemberKinds == [.method])
    }

    @Test(arguments: [CodeArtifact.SourceLanguage.java, .kotlin, .dart])
    func javaKotlinAndDartAlsoScanInitializers(language: CodeArtifact.SourceLanguage) throws {
        let parser = try #require(AnalysisService.standardParsers.first { $0.language == language })
        #expect(parser.configuration.deadCodeMemberKinds == [.method, .initializer])
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

    /// Why Kotlin now accepts `.initializer`: a bare construction reaches the shared
    /// `CallSiteScope.bareCall`, which resolves it to the constructor's fixed `init` member instead
    /// of dropping it, for both the primary and a secondary constructor.
    @Test func kotlinRecordsAConstructorCall() throws {
        let sites = try callSites("""
        class Thing(val x: Int) {
            constructor() : this(0) {}
            fun use() {
                val made = Thing(1)
                val empty = Thing()
            }
        }
        """, in: "use", of: KotlinCodeParser(), fileName: "Thing.kt")

        #expect(sites.count == 2)
        #expect(sites.allSatisfy { $0.receiver == .type("Thing") && $0.methodName == "init" })
    }

    @Test func kotlinExtractsAnOperatorGetAsAMethod() throws {
        let kinds = try memberKinds("""
        class Grid {
            operator fun get(i: Int): Int = i
        }
        """, of: KotlinCodeParser(), fileName: "Grid.kt")
        #expect(kinds["get"] == .method)
    }

    /// Why Java now accepts `.initializer`: `new Thing()` resolves the same way a static
    /// `Thing.method()` call would — the constructor's member is named after the type itself.
    @Test func javaRecordsAConstructorCall() throws {
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

        #expect(sites.count == 2)
        #expect(sites.allSatisfy { $0.receiver == .type("Thing") && $0.methodName == "Thing" })
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

    /// Why Dart now accepts `.initializer`: a bare default-constructor call `Thing()` now resolves
    /// through `CallSiteScope.bareCall`'s constructor opt-in, named after the type itself; a named
    /// constructor call `Thing.named()` already resolved — it shares the `TypeName.method()` grammar
    /// shape, not `bareCall`'s.
    @Test func dartRecordsConstructorCalls() throws {
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

        #expect(sites.count == 2)
        #expect(sites.contains { $0.receiver == .type("Thing") && $0.methodName == "Thing" })
        #expect(sites.contains { $0.receiver == .type("Thing") && $0.methodName == "named" })
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

    /// The end-to-end consequence for Java: a called constructor is not reported, while an uncalled
    /// one now is. Java's package-private default keeps both out of the public-API exemption.
    @Test func aCalledJavaConstructorIsNotReportedWhileAnUncalledOneIs() {
        let artifact = JavaCodeParser().parse(source: """
        class Called {
            Called() {}
        }
        class Uncalled {
            Uncalled() {}
        }
        class Worker {
            void run() {
                new Called();
            }
        }
        """, fileName: "Worker.java")
        let report = DeadCodeScan(
            artifact: artifact, languages: artifact.standardLanguageResolver).report
        #expect(report.candidates.map(\.id).contains("Uncalled.Uncalled"))
        #expect(!report.candidates.map(\.id).contains("Called.Called"))
    }

    /// The end-to-end consequence for Kotlin: a called constructor is not reported, while an
    /// uncalled one now is. Marked `private` since Kotlin's own default is `public`, which would
    /// otherwise exempt both as public API regardless of calls.
    @Test func aCalledKotlinConstructorIsNotReportedWhileAnUncalledOneIs() {
        let artifact = KotlinCodeParser().parse(source: """
        private class Called(val x: Int)
        private class Uncalled(val y: Int)
        class Worker {
            fun run() {
                Called(1)
            }
        }
        """, fileName: "Worker.kt")
        let report = DeadCodeScan(
            artifact: artifact, languages: artifact.standardLanguageResolver).report
        #expect(report.candidates.map(\.id).contains("Uncalled.init"))
        #expect(!report.candidates.map(\.id).contains("Called.init"))
    }

    /// The end-to-end consequence for Dart's default constructors: a called one is not reported,
    /// while an uncalled one now is. The class names are `_`-prefixed since Dart's own default is
    /// public, which would otherwise exempt both as public API regardless of calls.
    @Test func aCalledDartDefaultConstructorIsNotReportedWhileAnUncalledOneIs() {
        let artifact = DartCodeParser().parse(source: """
        class _Called {
          _Called();
        }
        class _Uncalled {
          _Uncalled();
        }
        class Worker {
          void run() {
            _Called();
          }
        }
        """, fileName: "worker.dart")
        let report = DeadCodeScan(
            artifact: artifact, languages: artifact.standardLanguageResolver).report
        #expect(report.candidates.map(\.id).contains("_Uncalled._Uncalled"))
        #expect(!report.candidates.map(\.id).contains("_Called._Called"))
    }

    /// The end-to-end consequence for Dart's named constructors: a called one is not reported, while
    /// an uncalled one now is.
    @Test func aCalledDartNamedConstructorIsNotReportedWhileAnUncalledOneIs() {
        let artifact = DartCodeParser().parse(source: """
        class Widget {
          Widget._calledNamed();
          Widget._uncalledNamed();
        }
        class Worker {
          void run() {
            Widget._calledNamed();
          }
        }
        """, fileName: "worker.dart")
        let report = DeadCodeScan(
            artifact: artifact, languages: artifact.standardLanguageResolver).report
        #expect(report.candidates.map(\.id).contains("Widget._uncalledNamed"))
        #expect(!report.candidates.map(\.id).contains("Widget._calledNamed"))
    }
}
