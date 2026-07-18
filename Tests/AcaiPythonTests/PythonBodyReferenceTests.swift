import Testing
@testable import AcaiCore
@testable import AcaiPython

@Suite("Python: Body Type References")
struct PythonBodyReferenceTests {
    @Test func capturesConstructionInMethodBody() {
        let source = """
        class Widget:
            pass

        class Factory:
            def build(self):
                w = Widget()
                return w
        """
        let artifact = PythonCodeParser().parse(source: source, fileName: "factory.py")
        let build = artifact.types.first { $0.name == "Factory" }?.members.first { $0.name == "build" }
        #expect(build?.referencedTypeNames.contains("Widget") == true)
    }
}
