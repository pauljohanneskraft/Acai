import Testing
@testable import UMLCore
@testable import UMLJVM

@Suite("Java Type Resolution & Consistency Tests")
struct JavaTypeResolutionTests {
    let parser = JavaCodeParser()

    // MARK: - Relationship Resolution

    @Test func relationshipsResolvedInSameFile() {
        let source = """
        package com.example;

        public class Animal {
            private String name;
        }

        public class Dog extends Animal implements Comparable<Dog> {
            private String breed;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Animals.java")

        let inheritance = artifact.relationships.first { $0.kind == .inheritance }
        #expect(inheritance?.source == "com.example.Dog")
        // Same-file target must be resolved to the qualified ID.
        #expect(inheritance?.target == "com.example.Animal")
    }

    @Test func inheritedTypesAreResolvedInSameFile() {
        let source = """
        package com.example;

        public interface Identifiable {
            String getId();
        }

        public class Entity implements Identifiable {
            public String getId() { return ""; }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Entities.java")
        let entity = artifact.types.first { $0.name == "Entity" }!
        // inheritedTypes should use qualified IDs for same-file types.
        #expect(entity.inheritedTypes.contains { $0.name == "com.example.Identifiable" })
    }

    @Test func crossFileRelationshipsStayAsSimpleNames() {
        let source = """
        package com.example.app;

        public class Dog extends Animal implements Serializable {
            private String breed;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Dog.java")
        let inheritance = artifact.relationships.first { $0.kind == .inheritance }
        #expect(inheritance?.source == "com.example.app.Dog")
        // "Animal" is not in this file, stays as-is.
        #expect(inheritance?.target == "Animal")
    }

    // MARK: - Nested Type IDs

    @Test func nestedTypeHasCorrectQualifiedId() {
        let source = """
        package com.example;

        public class Outer {
            public class Inner {
                private String value;
            }

            public static class StaticNested {
                private int count;
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Outer.java")
        let outer = artifact.types.first { $0.name == "Outer" }!
        let inner = outer.nestedTypes.first { $0.name == "Inner" }!
        let staticNested = outer.nestedTypes.first { $0.name == "StaticNested" }!

        // Nested type IDs must include the parent type.
        #expect(inner.id == "com.example.Outer.Inner")
        #expect(inner.qualifiedName == "com.example.Outer.Inner")
        #expect(staticNested.id == "com.example.Outer.StaticNested")
        #expect(staticNested.qualifiedName == "com.example.Outer.StaticNested")
    }

    @Test func deeplyNestedTypeIds() {
        let source = """
        package com.example;

        public class Outer {
            public class Middle {
                public class Inner {
                    private String value;
                }
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Outer.java")
        let outer = artifact.types.first { $0.name == "Outer" }!
        let middle = outer.nestedTypes.first { $0.name == "Middle" }!
        let inner = middle.nestedTypes.first { $0.name == "Inner" }!

        #expect(outer.id == "com.example.Outer")
        #expect(middle.id == "com.example.Outer.Middle")
        #expect(inner.id == "com.example.Outer.Middle.Inner")
    }

    @Test func nestedTypeRelationshipsUseCorrectIds() {
        let source = """
        package com.example;

        public class Result {
            public interface Listener {
                void onResult(Result result);
            }

            public class Success extends Result {
                private String value;
            }

            public class Failure extends Result {
                private Throwable error;
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Result.java")
        let rels = artifact.relationships.filter { $0.kind == .inheritance }
        #expect(rels.count == 2)
        // Sources must be the fully qualified nested type IDs.
        #expect(rels.contains { $0.source == "com.example.Result.Success" })
        #expect(rels.contains { $0.source == "com.example.Result.Failure" })
        // Targets must point to the parent.
        #expect(rels.allSatisfy { $0.target == "com.example.Result" })
    }

    // MARK: - All Same-File Relationships Qualified

    @Test func allSameFileRelationshipsAreQualified() {
        let source = """
        package com.example.domain;

        public interface Identifiable {
            String getId();
        }

        public interface Named {
            String getName();
        }

        public abstract class BaseEntity implements Identifiable {
            public String getId() { return ""; }
        }

        public class User extends BaseEntity implements Named {
            public String getName() { return ""; }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Domain.java")

        // All relationships in the same file should have qualified source and target.
        for rel in artifact.relationships {
            #expect(
                rel.source.contains("com.example.domain"),
                "source '\(rel.source)' should be qualified"
            )
            #expect(
                rel.target.contains("com.example.domain"),
                "target '\(rel.target)' should be qualified"
            )
        }
    }

    // MARK: - Enum with Interface in Package

    @Test func enumWithInterfaceInSameFile() {
        let source = """
        package com.example;

        public interface Displayable {
            String display();
        }

        public enum Color implements Displayable {
            RED, GREEN, BLUE;
            public String display() { return name(); }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Color.java")
        let conformance = artifact.relationships.first { $0.kind == .conformance }
        #expect(conformance?.source == "com.example.Color")
        #expect(conformance?.target == "com.example.Displayable")
    }

    // MARK: - Nested Enum in Package

    @Test func nestedEnumHasCorrectId() {
        let source = """
        package com.example;

        public class Order {
            public enum Status {
                PENDING, PROCESSING, COMPLETED
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Order.java")
        let order = artifact.types.first { $0.name == "Order" }!
        let status = order.nestedTypes.first { $0.name == "Status" }!
        #expect(status.id == "com.example.Order.Status")
    }

    // MARK: - Multi-File Simulation

    @Test func multiFileInheritanceProducesResolvableRelationship() {
        let source1 = """
        package com.example;

        public class Animal {
            private String name;
        }
        """
        let source2 = """
        package com.example;

        public class Dog extends Animal {
            private String breed;
        }
        """
        let artifact1 = parser.parse(source: source1, fileName: "Animal.java")
        let artifact2 = parser.parse(source: source2, fileName: "Dog.java")
        let merged = artifact1.merging(with: artifact2)

        let inheritance = merged.relationships.first { $0.kind == .inheritance }
        #expect(inheritance?.source == "com.example.Dog")
        // Target is just "Animal" because it's not defined in Dog.java.
        #expect(inheritance?.target == "Animal")

        #expect(merged.types.contains { $0.id == "com.example.Animal" })
        #expect(merged.types.contains { $0.id == "com.example.Dog" })
    }

    @Test func multiFileInterfaceConformanceRelationship() {
        let source1 = """
        package com.example;

        public interface Serializable {
            String serialize();
        }
        """
        let source2 = """
        package com.example;

        public class User implements Serializable {
            public String serialize() { return ""; }
        }
        """
        let artifact1 = parser.parse(source: source1, fileName: "Serializable.java")
        let artifact2 = parser.parse(source: source2, fileName: "User.java")
        let merged = artifact1.merging(with: artifact2)

        let conformance = merged.relationships.first { $0.kind == .conformance }
        #expect(conformance?.source == "com.example.User")
        #expect(conformance?.target == "Serializable")

        #expect(merged.types.contains { $0.id == "com.example.Serializable" })
        #expect(merged.types.contains { $0.id == "com.example.User" })
    }
}
