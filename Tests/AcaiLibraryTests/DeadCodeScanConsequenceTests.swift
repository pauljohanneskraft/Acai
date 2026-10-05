import Testing
import AcaiCore
import AcaiDiagram
@testable import AcaiLibrary

/// The observable consequence of `LanguageConfiguration.deadCodeMemberKinds`, taken through the real
/// registry rather than a fixture configuration: for each language that opts `.initializer` in, a
/// called constructor is not reported while an uncalled one is, and a kind a language declines stays
/// unreported however little it is used. `DeadCodeMemberKindAuditTests` pins the claims and the
/// parser behaviour these rest on.
@Suite("Dead-code scan consequences")
struct DeadCodeScanConsequenceTests {

    /// An uncalled Swift initializer and subscript are not reported, while an uncalled method still is.
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

    /// The end-to-end consequence for TypeScript: a called constructor is not reported, while an
    /// uncalled one now is. Both are `private`, since a TS member's own default is public, which
    /// would otherwise exempt them as public API regardless of calls. JavaScript has no spelling for
    /// a non-public constructor, so there every constructor stays exempt and only the call-graph edge
    /// above is observable.
    @Test func aCalledTypeScriptConstructorIsNotReportedWhileAnUncalledOneIs() {
        let artifact = JSCodeParser().parse(source: """
        class Called {
            private constructor() {}
        }
        class Uncalled {
            private constructor() {}
        }
        class Worker {
            run() {
                new Called();
            }
        }
        """, fileName: "Worker.ts")
        let report = DeadCodeScan(
            artifact: artifact, languages: artifact.standardLanguageResolver).report
        #expect(report.candidates.map(\.id).contains("Uncalled.constructor"))
        #expect(!report.candidates.map(\.id).contains("Called.constructor"))
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
