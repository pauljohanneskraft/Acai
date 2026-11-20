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

    /// Nothing in an interface body spells `public`, yet everything in one is public. A body-less
    /// method is implicitly abstract and a field implicitly `static final`.
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

    /// Java 9 allows an explicitly private interface method, which must not be promoted.
    @Test func explicitlyPrivateInterfaceMemberKeepsItsAccessLevel() {
        let members = members(ofInterfaceIn: """
        interface Priced {
            private double raw() { return 0.0; }
        }
        """)
        #expect(members.first { $0.name == "raw" }?.accessLevel == .private)
    }

    /// An annotation type's elements are public and abstract for the same reason.
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

    /// A class body resolves `Util.helper()` against the file's declared types; an interface body
    /// built no scope at all, so a default method's calls went unresolved.
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

    /// An enum reaches the same scope by a longer route: its declarations hang off an
    /// `enum_body_declarations` child, which was already extracted as a class body. Pinned so that
    /// building the scope on the enum body itself is known not to have displaced it.
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
