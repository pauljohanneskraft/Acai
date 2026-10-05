import Testing
@testable import AcaiCFamily
@testable import AcaiCore

/// C++ is the one language whose construction has no call syntax at all: every form below is a
/// `declaration` or a `new_expression` rather than a `call_expression`, so each needs its own
/// recognition before a constructor can have an incoming call-graph edge.
@Suite("C++: Construction call sites")
struct CppConstructionCallSiteTests {
    let parser = CppCodeParser()

    private func callSites(in memberName: String, of source: String) throws -> [CallSite] {
        let artifact = parser.parse(source: source, fileName: "factory.cpp")
        let member = try #require(
            artifact.flattened().flatMap(\.members).first { $0.name == memberName })
        return member.callSites
    }

    private static let declarationForms = """
    class Thing {
    public:
        Thing() {}
        Thing(int n) {}
    };
    class Factory {
    public:
        void build() {
            Thing plain;
            Thing parenthesized(1);
            Thing braced{1};
            Thing several[3];
        }
    };
    """

    @Test func everyDeclarationFormTargetsTheConstructor() throws {
        let sites = try callSites(in: "build", of: Self.declarationForms)
        #expect(sites.count == 4)
        #expect(sites.allSatisfy { $0.receiver == .type("Thing") && $0.methodName == "Thing" })
    }

    @Test func heapAllocationTargetsTheConstructor() throws {
        let sites = try callSites(in: "build", of: """
        class Thing {
        public:
            Thing(int n) {}
        };
        class Factory {
        public:
            void build() {
                Thing* owned = new Thing(1);
                delete owned;
            }
        };
        """)
        #expect(sites == [CallSite(receiver: .type("Thing"), methodName: "Thing",
                                   location: sites.first?.location)])
    }

    /// `Thing t = Thing(1);` constructs once. The initializer is a `call_expression` the walker
    /// resolves in its own right, so the declaration around it must not record a second edge.
    @Test func anExplicitlyInitializedDeclarationRecordsOneConstruction() throws {
        let sites = try callSites(in: "build", of: """
        class Thing {
        public:
            Thing(int n) {}
        };
        class Factory {
        public:
            void build() { Thing copied = Thing(1); }
        };
        """)
        #expect(sites.count == 1)
        #expect(sites.first?.receiver == .type("Thing"))
        #expect(sites.first?.methodName == "Thing")
    }

    /// A temporary resolves to the constructor rather than to a `.selfDispatch` call named after
    /// the type, which the call-graph builder would otherwise try against the enclosing type.
    @Test func aTemporaryTargetsTheConstructor() throws {
        let sites = try callSites(in: "build", of: """
        class Thing {
        public:
            Thing(int n) {}
        };
        class Factory {
        public:
            void build() { Thing(1); }
        };
        """)
        #expect(sites.map(\.receiver) == [.type("Thing")])
        #expect(sites.map(\.methodName) == ["Thing"])
    }

    /// A pointer or reference binding constructs nothing, a prototype is not the most-vexing-parse
    /// construction it resembles, and a standard-library declaration must not reach the call graph
    /// at all.
    @Test func declarationsThatConstructNothingRecordNoCall() throws {
        let sites = try callSites(in: "build", of: """
        class Thing {
        public:
            Thing() {}
        };
        class Factory {
        public:
            void build() {
                Thing* pointer;
                Thing makeOne();
                int count = 0;
                std::string text;
                std::vector<Thing> many;
            }
        };
        """)
        #expect(sites.isEmpty)
    }

    /// A construction of a type declared in another file defers to the post-merge pass rather than
    /// being dropped, the same way `Type::method()` on an undeclared type already does.
    @Test func aConstructionOfATypeDeclaredElsewhereIsDeferred() throws {
        let sites = try callSites(in: "build", of: """
        class Factory {
        public:
            void build() { Widget made; }
        };
        """)
        #expect(sites.map(\.receiver) == [.unresolvedTypeName("Widget")])
        #expect(sites.map(\.methodName) == ["Widget"])
    }

    /// C is out of scope entirely: it has no constructors, so a declaration there has no member to
    /// target and an edge for it could never resolve.
    @Test func aCDeclarationOfAKnownStructRecordsNoCall() throws {
        let artifact = CCodeParser().parse(source: """
        struct Thing {
            int size;
        };

        void build(void) {
            struct Thing made;
            Thing plain;
        }
        """, fileName: "factory.c")
        let build = try #require(artifact.freestandingFunctions.first { $0.name == "build" })
        #expect(build.callSites.isEmpty)
    }

    @Test func aFreeFunctionBodyRecordsItsConstructions() throws {
        let artifact = parser.parse(source: """
        class Thing {
        public:
            Thing() {}
        };
        void build() { Thing made; }
        """, fileName: "factory.cpp")
        let build = try #require(artifact.freestandingFunctions.first { $0.name == "build" })
        #expect(build.callSites.map(\.receiver) == [.type("Thing")])
        #expect(build.callSites.map(\.methodName) == ["Thing"])
    }
}
