import Testing
@testable import UMLCFamily
@testable import UMLCore

@Suite("C++: Type Tests")
struct CppTests {
    let parser = CppCodeParser()

    @Test func classWithAccessSpecifiers() {
        let source = """
        class Account {
        public:
            void deposit(double amount);
            double balance() const;
        private:
            double balance_;
            int id_;
        };
        """
        let artifact = parser.parse(source: source, fileName: "account.cpp")
        #expect(artifact.metadata.sourceLanguage == .cpp)
        let account = artifact.types.first { $0.name == "Account" }
        #expect(account?.kind == .class)
        let deposit = account?.members.first { $0.name == "deposit" }
        #expect(deposit?.kind == .method)
        #expect(deposit?.accessLevel == .public)
        let balanceField = account?.members.first { $0.name == "balance_" }
        #expect(balanceField?.kind == .property)
        #expect(balanceField?.accessLevel == .private)
    }

    @Test func inheritance() {
        let source = """
        class Shape {
        public:
            virtual double area() const = 0;
        };

        class Circle : public Shape {
        public:
            double area() const override;
        private:
            double radius_;
        };
        """
        let artifact = parser.parse(source: source, fileName: "shapes.cpp")
        #expect(artifact.types.contains { $0.name == "Shape" })
        let circle = artifact.types.first { $0.name == "Circle" }
        #expect(circle?.inheritedTypes.contains { $0.name == "Shape" } == true)
        #expect(artifact.relationships.contains { $0.kind == .inheritance && $0.target == "Shape" })
        // The pure virtual `area() const = 0` is recorded as abstract.
        let area = artifact.types.first { $0.name == "Shape" }?.members.first { $0.name == "area" }
        #expect(area?.modifiers.contains(.abstract) == true)
    }

    @Test func namespaceQualifiesType() {
        let source = """
        namespace banking {
            struct Money {
                long cents;
            };
        }
        """
        let artifact = parser.parse(source: source, fileName: "money.cpp")
        let money = artifact.types.first { $0.name == "Money" }
        #expect(money?.namespace == "banking")
        #expect(money?.qualifiedName == "banking.Money")
    }

    @Test func templateClass() {
        let source = """
        template <typename T>
        class Box {
        public:
            T value;
            T get() const;
        };
        """
        let artifact = parser.parse(source: source, fileName: "box.cpp")
        let box = artifact.types.first { $0.name == "Box" }
        #expect(box?.genericParameters.contains { $0.name == "T" } == true)
    }

    @Test func collectionFieldIsAggregation() {
        let source = """
        #include <vector>
        class Roster {
        public:
            std::vector<Player> players;
        };
        class Player {};
        """
        let artifact = parser.parse(source: source, fileName: "roster.cpp")
            .enriched(configuration: CppCodeParser().configuration)
        let aggregation = artifact.relationships.first {
            $0.kind == .aggregation && $0.label == "players"
        }
        #expect(aggregation != nil)
    }
}
