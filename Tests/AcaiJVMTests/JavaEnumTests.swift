import Testing
@testable import AcaiJVM
@testable import AcaiCore

@Suite("Java: Enum Tests")
struct JavaEnumTests {
    let parser = JavaCodeParser()

    @Test func enumDeclaration() {
        let source = """
        public enum Direction {
            NORTH, SOUTH, EAST, WEST;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Direction.java")
        #expect(artifact.types.count == 1)
        let dir = artifact.types[0]
        #expect(dir.kind == .enum)
        #expect(dir.enumCases.count == 4)
        #expect(dir.enumCases[0].name == "NORTH")
    }

    @Test func enumWithArguments() {
        let source = """
        public enum Planet {
            EARTH(5.976e+24, 6.37814e6),
            MARS(6.421e+23, 3.3972e6);

            private final double mass;
            private final double radius;

            Planet(double mass, double radius) {
                this.mass = mass;
                this.radius = radius;
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Planet.java")
        let planet = artifact.types[0]
        #expect(planet.kind == .enum)
        #expect(planet.enumCases.count == 2)
        #expect(planet.enumCases[0].name == "EARTH")
        #expect(planet.enumCases[1].name == "MARS")
    }

    @Test func enumWithInterfaces() {
        let source = """
        public enum Operation implements Calculator {
            ADD, SUBTRACT, MULTIPLY, DIVIDE;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Operation.java")
        let operation = artifact.types[0]
        #expect(operation.kind == .enum)

        let conformance = artifact.relationships.first { $0.kind == .conformance }
        #expect(conformance != nil)
        #expect(conformance?.target == "Calculator")
    }

}
