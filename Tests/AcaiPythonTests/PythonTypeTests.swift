import Testing
@testable import AcaiPython
@testable import AcaiCore

@Suite("Python: Type Tests")
struct PythonTypeTests {
    let parser = PythonCodeParser()

    @Test func classDeclaration() {
        let source = """
        class User:
            def __init__(self, name, age):
                self.name = name
                self.age = age
        """
        let artifact = parser.parse(source: source, fileName: "user.py")
        #expect(artifact.types.count == 1)
        let user = artifact.types[0]
        #expect(user.name == "User")
        #expect(user.kind == .class)
    }

    @Test func singleInheritance() {
        let source = """
        class Animal:
            pass

        class Dog(Animal):
            pass
        """
        let artifact = parser.parse(source: source, fileName: "animals.py")
        #expect(artifact.types.count == 2)
        let dog = artifact.types.first { $0.name == "Dog" }
        #expect(dog?.inheritedTypes.map(\.name) == ["Animal"])
        #expect(artifact.relationships.contains {
            $0.kind == .inheritance && $0.target == "Animal"
        })
    }

    @Test func enumDetection() {
        let source = """
        from enum import Enum

        class Color(Enum):
            RED = 1
            GREEN = 2
            BLUE = 3
        """
        let artifact = parser.parse(source: source, fileName: "color.py")
        let color = artifact.types.first { $0.name == "Color" }
        #expect(color?.kind == .enum)
        #expect(color?.enumCases.map(\.name) == ["RED", "GREEN", "BLUE"])
        #expect(color?.enumCases.first?.rawValue == "1")
    }

    @Test func protocolDetection() {
        let source = """
        from typing import Protocol

        class Drawable(Protocol):
            def draw(self) -> None: ...
        """
        let artifact = parser.parse(source: source, fileName: "drawable.py")
        let drawable = artifact.types.first { $0.name == "Drawable" }
        #expect(drawable?.kind == .protocol)
    }

    @Test func abstractBaseClass() {
        let source = """
        from abc import ABC, abstractmethod

        class Shape(ABC):
            @abstractmethod
            def area(self) -> float: ...
        """
        let artifact = parser.parse(source: source, fileName: "shape.py")
        let shape = artifact.types.first { $0.name == "Shape" }
        #expect(shape?.modifiers.contains(.abstract) == true)
        let area = shape?.members.first { $0.name == "area" }
        #expect(area?.modifiers.contains(.abstract) == true)
    }

    @Test func dataclassStereotype() {
        let source = """
        from dataclasses import dataclass

        @dataclass
        class Point:
            x: int
            y: int
        """
        let artifact = parser.parse(source: source, fileName: "point.py")
        let point = artifact.types.first { $0.name == "Point" }
        #expect(point?.annotations.contains("dataclass") == true)
    }

    @Test func nestedClass() {
        let source = """
        class Outer:
            class Inner:
                pass
        """
        let artifact = parser.parse(source: source, fileName: "nested.py")
        let outer = artifact.types.first { $0.name == "Outer" }
        #expect(outer?.nestedTypes.map(\.name) == ["Inner"])
    }

    /// A nested type's id is qualified with its enclosing type so it doesn't collide with a
    /// top-level type sharing the same simple name.
    @Test func nestedTypeIDIsQualified() {
        let source = """
        class Inner:
            pass

        class Outer:
            class Inner:
                pass
        """
        let artifact = parser.parse(source: source, fileName: "collision.py")
        let topLevelInner = artifact.types.first { $0.name == "Inner" }
        let outer = artifact.types.first { $0.name == "Outer" }
        let nestedInner = outer?.nestedTypes.first { $0.name == "Inner" }

        #expect(topLevelInner?.id == "Inner")
        #expect(nestedInner?.id == "Outer.Inner")
        #expect(nestedInner?.qualifiedName == "Outer.Inner")
        // The two distinct `Inner` types must not share an id.
        #expect(topLevelInner?.id != nestedInner?.id)
    }

    /// A nested type's inheritance edge uses its qualified id as the source, so id-based edge
    /// pruning (`removingTypes`, keyed on `TypeDeclaration.id`) matches it without a dangling edge.
    @Test func nestedTypeRelationshipUsesQualifiedSource() {
        let source = """
        class Base:
            pass

        class Outer:
            class Inner(Base):
                pass
        """
        let artifact = parser.parse(source: source, fileName: "nested_rel.py")
        let inheritance = artifact.relationships.first { $0.kind == .inheritance && $0.target == "Base" }
        #expect(inheritance?.source == "Outer.Inner")
    }

    @Test func genericBase() {
        let source = """
        from typing import Generic, TypeVar

        T = TypeVar("T")

        class Box(Generic[T]):
            pass
        """
        let artifact = parser.parse(source: source, fileName: "box.py")
        let box = artifact.types.first { $0.name == "Box" }
        #expect(box?.genericParameters.map(\.name) == ["T"])
    }
}
