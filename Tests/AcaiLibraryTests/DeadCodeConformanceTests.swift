import Testing
import AcaiCore
import AcaiDiagram
@testable import AcaiLibrary

@Suite("Dead-code conformance through the real parsers")
struct DeadCodeConformanceTests {

    private func candidates<Parser: CodeParser>(_ parser: Parser, _ source: String, file: String) -> Set<String> {
        let artifact = parser.parse(source: source, fileName: file).enriched(configuration: parser.configuration)
        return Set(DeadCodeScan(artifact: artifact, languages: artifact.standardLanguageResolver)
            .report.candidates.map(\.id))
    }

    private func swift(_ source: String) -> Set<String> {
        candidates(SwiftCodeParser(), source, file: "Fixture.swift")
    }

    @Test func aNestedProtocolsWitnessIsLive() {
        let dead = swift("""
        enum Host { protocol Runnable { func start() } }
        struct Tool: Host.Runnable {
            func start() {}
            func orphan() {}
        }
        """)
        #expect(dead == ["Tool.orphan()"])
    }

    @Test func aConformanceDeclaredOnAnExtensionCoversTheTypesMembers() {
        let dead = swift("""
        protocol Runnable { func start() }
        struct Tool { func start() {} }
        extension Tool: Runnable {}
        """)
        #expect(dead.isEmpty)
    }

    @Test func aMemberDeclaredInAConformingExtensionIsAWitness() {
        let dead = swift("""
        protocol Runnable { func start() }
        struct Tool {}
        extension Tool: Runnable { func start() {} }
        """)
        #expect(dead.isEmpty)
    }

    @Test func aSubclassWitnessesItsSuperclasssConformance() {
        let dead = swift("""
        protocol Runnable { func start() }
        extension Runnable { func start() {} }
        class Base: Runnable {}
        class Sub: Base {
            func start() {}
            func stop() {}
        }
        """)
        #expect(dead == ["Sub.stop()"])
    }

    @Test func aSameNamedOverloadOfAWitnessIsReported() {
        let dead = swift("""
        protocol Runnable { func start() }
        struct Tool: Runnable {
            func start() {}
            func start(after delay: Int) {}
        }
        """)
        #expect(dead == ["Tool.start(after:Int)"])
    }

    /// No overload matches the requirement's labels, so every same-named member stays a witness.
    @Test func aWitnessWhoseLabelsDifferFromTheRequirementStaysLive() {
        let dead = swift("""
        protocol Store { associatedtype Item; func put(_ item: Item) }
        struct Box: Store { func put(item: Int) {} }
        """)
        #expect(dead.isEmpty)
    }

    @Test func onlyAParsableCommandsRunIsAnEntryPoint() {
        let dead = swift("""
        import ArgumentParser
        struct Build: ParsableCommand { func run() {} }
        final class Scheduler { func run() {} }
        """)
        #expect(dead == ["Scheduler.run()"])
    }

    @Test func aSameNamedProtocolInAnotherScopeLendsNoRequirements() {
        let dead = swift("""
        protocol Runnable { func start() }
        enum Host { protocol Runnable { func stop() } }
        struct Tool: Host.Runnable {
            func start() {}
            func stop() {}
        }
        """)
        #expect(dead == ["Tool.start()"])
    }

    /// Asserted on the markers because Dart's public-by-name rule already exempts these members in a scan.
    @Test func dartsLifecycleMarkersNeedAWidgetSupertype() throws {
        let parser = DartCodeParser()
        let artifact = parser.parse(
            source: "class _S extends State<Counter> { void dispose() {} }", fileName: "counter.dart")
        let type = try #require(artifact.types.first { $0.name == "_S" })
        let dispose = try #require(type.members.first { $0.name == "dispose" })
        let markers = parser.configuration.entryPointMarkers
        #expect(markers.marks(dispose, inheritingFrom: Set(type.inheritedTypes.map(\.name))))
        #expect(!markers.marks(dispose, inheritingFrom: []))
    }

    @Test func pythonsInitializerIsNotAMarker() {
        let markers = PythonCodeParser().configuration.entryPointMarkers
        let initializer = Member(name: "__init__", kind: .initializer, accessLevel: .public)
        let hook = Member(name: "setup_method", kind: .method, accessLevel: .public)
        #expect(!markers.marks(initializer, inheritingFrom: []))
        #expect(markers.marks(hook, inheritingFrom: []))
    }
}
