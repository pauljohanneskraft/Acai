import Testing
@testable import AcaiJVM
@testable import AcaiCore

@Suite("Java: Interface Tests")
struct JavaInterfaceTests {
    let parser = JavaCodeParser()

    @Test func interfaceDeclaration() {
        let source = """
        public interface Repository<T> {
            T findById(String id);
            List<T> findAll();
        }
        """
        let artifact = parser.parse(source: source, fileName: "Repository.java")
        #expect(artifact.types.count == 1)
        let repo = artifact.types[0]
        #expect(repo.kind == .interface)
        #expect(repo.genericParameters.count == 1)
        #expect(repo.members.count == 2)
    }

    @Test func interfaceExtends() {
        let source = """
        public interface ExtendedRepository extends Repository, Serializable {
        }
        """
        let artifact = parser.parse(source: source, fileName: "ExtendedRepository.java")

        let conformances = artifact.relationships.filter { $0.kind == .conformance }
        #expect(conformances.count == 2)
    }

    private func members(ofInterfaceIn source: String) -> [Member] {
        parser.parse(source: source, fileName: "Priced.java")
            .types.first { $0.name == "Priced" }?.members ?? []
    }

    @Test func interfaceMembersAreImplicitlyPublic() {
        let members = members(ofInterfaceIn: """
        interface Priced {
            int SCALE = 100;

            double price();

            default double discounted() { return price(); }

            static Priced zero() { return null; }
        }
        """)

        let price = members.first { $0.name == "price" }
        #expect(price?.accessLevel == .public)
        #expect(price?.modifiers.contains(.abstract) == true)

        let scale = members.first { $0.name == "SCALE" }
        #expect(scale?.accessLevel == .public)
        #expect(scale?.modifiers.contains(.static) == true)
        #expect(scale?.modifiers.contains(.final) == true)

        // A method with a body is not abstract, however it got one.
        let discounted = members.first { $0.name == "discounted" }
        #expect(discounted?.accessLevel == .public)
        #expect(discounted?.modifiers.contains(.abstract) == false)
        #expect(members.first { $0.name == "zero" }?.modifiers.contains(.abstract) == false)
    }

    @Test func explicitlyPrivateInterfaceMemberKeepsItsAccessLevel() {
        let members = members(ofInterfaceIn: """
        interface Priced {
            private double raw() { return 0.0; }
        }
        """)
        #expect(members.first { $0.name == "raw" }?.accessLevel == .private)
    }

    @Test func annotationTypeElementsAreImplicitlyPublicAndAbstract() {
        let artifact = parser.parse(
            source: """
            @interface Audited {
                String value();
            }
            """,
            fileName: "Audited.java"
        )
        let value = artifact.types.first?.members.first { $0.name == "value" }
        #expect(value?.accessLevel == .public)
        #expect(value?.modifiers.contains(.abstract) == true)
    }

    @Test func defaultMethodResolvesACallToADeclaredType() {
        let artifact = parser.parse(
            source: """
            class Util {
                static double helper() { return 1.0; }
            }

            interface Priced {
                default double price() { return Util.helper(); }
            }
            """,
            fileName: "Priced.java"
        )
        let sites = artifact.types.first { $0.name == "Priced" }?
            .members.first { $0.name == "price" }?.callSites ?? []
        #expect(sites.contains { $0.methodName == "helper" && $0.receiverType == "Util" })
    }

    @Test func defaultMethodResolvesACallThroughAnInterfaceConstant() {
        let artifact = parser.parse(
            source: """
            class Helper {
                void run() {}
            }

            interface Priced {
                Helper HELPER = new Helper();

                default void price() { HELPER.run(); }
            }
            """,
            fileName: "Priced.java"
        )
        let sites = artifact.types.first { $0.name == "Priced" }?
            .members.first { $0.name == "price" }?.callSites ?? []
        #expect(sites.contains { $0.methodName == "run" && $0.receiverType == "Helper" })
    }

    @Test func typeNestedInAnInterfaceIsImplicitlyPublicAndStatic() {
        let artifact = parser.parse(
            source: """
            interface Outer {
                class Inner {}
            }

            class Host {
                class Inner {}
            }
            """,
            fileName: "Outer.java"
        )
        let inInterface = artifact.types.first { $0.name == "Outer" }?.nestedTypes.first
        #expect(inInterface?.accessLevel == .public)
        #expect(inInterface?.modifiers.contains(.static) == true)

        let inClass = artifact.types.first { $0.name == "Host" }?.nestedTypes.first
        #expect(inClass?.accessLevel == .packagePrivate)
        #expect(inClass?.modifiers.contains(.static) == false)
    }

    @Test func enumMethodResolvesACallToADeclaredType() {
        let artifact = parser.parse(
            source: """
            class Util {
                static double helper() { return 1.0; }
            }

            enum Category {
                FOOD;

                double price() { return Util.helper(); }
            }
            """,
            fileName: "Category.java"
        )
        let sites = artifact.types.first { $0.name == "Category" }?
            .members.first { $0.name == "price" }?.callSites ?? []
        #expect(sites.contains { $0.methodName == "helper" && $0.receiverType == "Util" })
    }
}
