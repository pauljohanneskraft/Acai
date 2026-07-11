import Testing
@testable import UMLCFamily
@testable import UMLCore

@Suite("C++: Body analysis (call sites + assignments)")
struct CppBodyAnalysisTests {
    let parser = CppCodeParser()

    @Test func resolvesCallSitesOnTypedReceivers() {
        let source = """
        class Checkout {
        public:
            void placeOrder() {
                inventory.reserve();
                this->charge();
            }
            void charge() {}
        private:
            Inventory inventory;
        };
        class Inventory {
        public:
            void reserve() {}
        };
        """
        let artifact = parser.parse(source: source, fileName: "checkout.cpp")
        let placeOrder = artifact.types
            .first { $0.name == "Checkout" }?
            .members.first { $0.name == "placeOrder" }
        let calls = placeOrder?.callSites ?? []
        #expect(calls.contains { $0.receiverType == "Inventory" && $0.methodName == "reserve" })
        #expect(calls.contains { $0.receiverType == nil && $0.methodName == "charge" })
    }

    /// A bare `foo()` inside a member function is an implicit `this->foo()` sibling call — captured
    /// as `.selfDispatch` (was `.free`, which the call-graph builder dropped since a member is not a
    /// freestanding function), so private sibling methods aren't false-flagged as dead (RC1).
    @Test func capturesBareSiblingMethodCall() {
        let source = """
        class Worker {
        public:
            void run() { helper(); }
        private:
            void helper() {}
        };
        """
        let artifact = parser.parse(source: source, fileName: "worker.cpp")
        let run = artifact.types
            .first { $0.name == "Worker" }?
            .members.first { $0.name == "run" }
        let calls = run?.callSites ?? []
        #expect(calls.contains { $0.methodName == "helper" && $0.receiver == .selfDispatch })
    }

    /// Calls in a member-initializer list (`: x(helper())`) or a default member initializer
    /// (`int y = compute();`) are recorded so their targets aren't false-flagged as dead (RC2).
    @Test func capturesMemberInitializerListAndDefaultInitializerCalls() {
        let source = """
        class Worker {
        public:
            Worker() : x(helper()) {}
        private:
            int helper() { return 1; }
            int x;
            int y = compute();
            int compute() { return 2; }
        };
        """
        let artifact = parser.parse(source: source, fileName: "worker.cpp")
        let members = artifact.types.first { $0.name == "Worker" }?.members ?? []
        let allSites = members.flatMap(\.callSites)
        #expect(allSites.contains { $0.methodName == "helper" })
        #expect(allSites.contains { $0.methodName == "compute" })
    }

    /// A local declared with an explicit type (`Helper h;`) or a pointer to a `new`-constructed type
    /// (`Helper* p = new Helper();`) resolves the receiver of `h.method()` / `p->method()` (RC4).
    @Test func resolvesLocalAndPointerReceivers() {
        let source = """
        class Helper {
        public:
            void doThing() {}
        };
        class Worker {
        public:
            void run() {
                Helper h;
                h.doThing();
                Helper* p = new Helper();
                p->doThing();
            }
        };
        """
        let artifact = parser.parse(source: source, fileName: "worker.cpp")
        let run = artifact.types
            .first { $0.name == "Worker" }?
            .members.first { $0.name == "run" }
        let sites = run?.callSites ?? []
        #expect(sites.filter { $0.methodName == "doThing" && $0.receiverType == "Helper" }.count == 2)
    }

    @Test func freeFunctionCallGraph() {
        let source = """
        void validateCart() {}
        void chargeCard() {}

        void submitOrder() {
            validateCart();
            chargeCard();
        }
        """
        let artifact = parser.parse(source: source, fileName: "order.cpp")
        let submit = artifact.freestandingFunctions.first { $0.name == "submitOrder" }
        let calledNames = Set((submit?.callSites ?? []).map(\.methodName))
        #expect(calledNames == ["validateCart", "chargeCard"])
    }

    @Test func scopedEnumAssignmentIsEnumCase() {
        let source = """
        enum class DownloadState { idle, downloading, finished };

        class Download {
        public:
            void start() {
                state = DownloadState::downloading;
            }
        private:
            DownloadState state;
        };
        """
        let artifact = parser.parse(source: source, fileName: "download.cpp")
        let start = artifact.types
            .first { $0.name == "Download" }?
            .members.first { $0.name == "start" }
        let assignment = start?.assignments.first { $0.targetName == "state" }
        #expect(assignment?.value.kind == .enumCase)
        #expect(assignment?.value.text == "downloading")
        #expect(assignment?.value.receiverTypeName == "DownloadState")
    }
}

@Suite("C: Body analysis (struct mutation in free functions)")
struct CBodyAnalysisTests {
    let parser = CCodeParser()

    @Test func structPointerMutationResolvesToReceiverTypeAndEnumCase() {
        // C has no methods: a free function mutates the struct through a typed pointer parameter,
        // and the unscoped enum constant on the right is an enumerable value.
        let source = """
        typedef enum { REQUESTED, DOWNLOADING, FINISHED } DownloadState;

        typedef struct {
            DownloadState state;
        } Download;

        void run(Download *download) {
            download->state = DOWNLOADING;
        }
        """
        let artifact = parser.parse(source: source, fileName: "download.c")
        let run = artifact.freestandingFunctions.first { $0.name == "run" }
        let assignment = run?.assignments.first { $0.targetName == "state" }
        #expect(assignment?.targetReceiver == "Download")
        #expect(assignment?.value.kind == .enumCase)
        #expect(assignment?.value.text == "DOWNLOADING")
    }

    @Test func nonParameterFieldMutationIsNotMisattributed() {
        // A field write through an unknown receiver (not a typed parameter) is dropped, so it can't
        // pollute a struct's state machine.
        let source = """
        void touch(void) {
            other->state = 1;
        }
        """
        let artifact = parser.parse(source: source, fileName: "touch.c")
        let touch = artifact.freestandingFunctions.first { $0.name == "touch" }
        #expect(touch?.assignments.contains { $0.targetName == "state" } == false)
    }
}
