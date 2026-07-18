import Testing
@testable import AcaiCore
@testable import AcaiJVM

@Suite("JVM: Body Type References")
struct JVMBodyReferenceTests {
    @Test func kotlinCapturesConstructionInFunctionBody() {
        let source = """
        class Widget
        class Factory {
            fun build() { val w = Widget() }
        }
        """
        let artifact = KotlinCodeParser().parse(source: source, fileName: "Factory.kt")
        let build = artifact.types.first { $0.name == "Factory" }?.members.first { $0.name == "build" }
        #expect(build?.referencedTypeNames.contains("Widget") == true)
    }

    @Test func javaCapturesConstructionInMethodBody() {
        let source = """
        class Widget {}
        class Factory {
            void build() { Widget w = new Widget(); }
        }
        """
        let artifact = JavaCodeParser().parse(source: source, fileName: "Factory.java")
        let build = artifact.types.first { $0.name == "Factory" }?.members.first { $0.name == "build" }
        #expect(build?.referencedTypeNames.contains("Widget") == true)
    }
}
