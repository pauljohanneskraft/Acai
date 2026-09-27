import Testing
@testable import AcaiCFamily
@testable import AcaiCore

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
        let shape = artifact.types.first { $0.name == "Shape" }
        let area = shape?.members.first { $0.name == "area" }
        #expect(area?.modifiers.contains(.abstract) == true)
        // A class with a pure-virtual member is itself abstract (counts as an interface); the subclass isn't.
        #expect(shape?.modifiers.contains(.abstract) == true)
        #expect(circle?.modifiers.contains(.abstract) == false)
    }

    @Test func nestedRecordIDIsQualified() {
        let source = """
        struct Inner {
            int a;
        };

        struct Outer {
            struct Inner {
                int b;
            };
        };
        """
        let artifact = parser.parse(source: source, fileName: "nested.cpp")
        let topLevelInner = artifact.types.first { $0.name == "Inner" }
        let outer = artifact.types.first { $0.name == "Outer" }
        let nestedInner = outer?.nestedTypes.first { $0.name == "Inner" }

        #expect(topLevelInner?.id == "Inner")
        #expect(nestedInner?.id == "Outer.Inner")
        #expect(topLevelInner?.id != nestedInner?.id)
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

    @Test func staticNamespaceFunctionHasFilePrivateAccessButStaticMethodDoesNot() {
        let source = """
        namespace detail {
        static int helper(int a) {
            return a * 2;
        }
        }

        class Counter {
        public:
            static int next();
        };
        """
        let artifact = parser.parse(source: source, fileName: "linkage.cpp")
        let helper = artifact.freestandingFunctions.first { $0.name == "helper" }
        #expect(helper?.accessLevel == .filePrivate)
        let counter = artifact.types.first { $0.name == "Counter" }
        let next = counter?.members.first { $0.name == "next" }
        #expect(next?.accessLevel == .public)
        #expect(next?.modifiers.contains(.static) == true)
    }

    /// A constructor *declared* in the class body is the ordinary header shape, and tree-sitter-cpp
    /// aliases it to `declaration` rather than `field_declaration` — so it needs its own case.
    @Test func constructorDeclaredInClassBody() {
        let source = """
        class Genre {};

        class Song {
        public:
            Song(const std::string &title, Genre genre);
            explicit Song(int id);
        private:
            int id_;
        };
        """
        let artifact = parser.parse(source: source, fileName: "song.cpp")
        let song = artifact.types.first { $0.name == "Song" }
        let initializers = song?.members.filter { $0.kind == .initializer } ?? []
        #expect(initializers.count == 2, "both declared constructors should appear")
        #expect(initializers.first?.accessLevel == .public)
        #expect(initializers.first?.type == nil, "a constructor has no return type")
        #expect(initializers.first?.parameters.map(\.internalName) == ["title", "genre"])
        let enriched = artifact.enriched(configuration: parser.configuration)
        #expect(
            enriched.relationships.contains { $0.kind == .dependency && $0.target == "Genre" },
            "a constructor parameter's declared type is a dependency")
    }
}
