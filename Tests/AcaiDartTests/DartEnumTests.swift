import Testing
@testable import AcaiDart
@testable import AcaiCore

@Suite("Dart: Enum Tests")
struct DartEnumTests {
    let parser = DartCodeParser()

    @Test func enumDeclaration() {
        let source = """
        enum Direction {
            north,
            south,
            east,
            west
        }
        """
        let artifact = parser.parse(source: source, fileName: "Direction.dart")
        #expect(artifact.types.count == 1)
        let dir = artifact.types[0]
        #expect(dir.kind == .enum)
        #expect(dir.enumCases.count == 4)
        #expect(dir.enumCases[0].name == "north")
        #expect(dir.enumCases[1].name == "south")
        #expect(dir.enumCases.allSatisfy { $0.rawValue == nil })
    }

    @Test func enhancedEnumConstantArgumentsBecomeTheRawValue() {
        let source = """
        enum Category {
          food(1, 'food'),
          tool(2, 'tool');

          const Category(this.code, this.label);

          final int code;
          final String label;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Category.dart")
        let category = artifact.types[0]
        #expect(category.enumCases.count == 2)
        #expect(category.enumCases[0].rawValue == "1, 'food'")
        #expect(category.enumCases[1].rawValue == "2, 'tool'")
        #expect(category.enumCases.allSatisfy { $0.associatedValues.isEmpty })
    }

    @Test func enumImplementsInterface() {
        let source = """
        abstract class Displayable {
            String display();
        }

        enum Color implements Displayable {
            red,
            green,
            blue;

            String display() => name;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Color.dart")
        let color = artifact.types.first { $0.name == "Color" }
        #expect(color?.kind == .enum)
        #expect(color?.enumCases.count == 3)

        let conformance = artifact.relationships.first { $0.kind == .conformance }
        #expect(conformance?.target == "Displayable")
    }
}
