import Testing
@testable import AcaiJVM
@testable import AcaiCore

@Suite("Java: Record Tests")
struct JavaRecordTests {
    let parser = JavaCodeParser()

    @Test func recordDeclaration() {
        let source = """
        public record Point(int x, int y) {}
        """
        let artifact = parser.parse(source: source, fileName: "Point.java")
        #expect(artifact.types.count == 1)
        let point = artifact.types[0]
        #expect(point.kind == .record)
        #expect(point.members.count >= 2) // x and y as properties
    }

    @Test func recordWithGenerics() {
        let source = """
        public record Box<T>(T value) {}
        """
        let artifact = parser.parse(source: source, fileName: "Box.java")
        let box = artifact.types[0]
        #expect(box.kind == .record)
        #expect(box.genericParameters.count == 1)
        #expect(box.members.count >= 1)
    }

    @Test func recordWithInterfaces() {
        let source = """
        public record Coordinate(double x, double y) implements Comparable<Coordinate> {}
        """
        let artifact = parser.parse(source: source, fileName: "Coordinate.java")
        let coordinate = artifact.types[0]
        #expect(coordinate.kind == .record)

        let conformance = artifact.relationships.first { $0.kind == .conformance }
        #expect(conformance != nil)
        #expect(conformance?.target.contains("Comparable") == true)
    }

}
