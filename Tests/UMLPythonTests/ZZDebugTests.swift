import Testing
@testable import UMLPython

@Suite("zzdebug")
struct ZZDebugTests {
    @Test func debugClassBodyField() {
        let source = """
        class Point:
            x: int
            y: int = 0
        """
        _ = PythonCodeParser().parse(source: source, fileName: "t.py")
    }

    @Test func debugParams() {
        let source = """
        class User:
            def __init__(self, name: str, age: int):
                self.name = name
        """
        _ = PythonCodeParser().parse(source: source, fileName: "t.py")
    }
}
