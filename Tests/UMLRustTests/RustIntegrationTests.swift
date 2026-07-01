import Testing
import UMLCore
import UMLDiagram
@testable import UMLRust

@Suite("Rust: Integration Tests")
struct RustIntegrationTests {
    let parser = RustCodeParser()

    @Test func implMethodsContributeCallSites() {
        let source = """
        pub struct PaymentGateway;

        impl PaymentGateway {
            pub fn authorize(&self) {}
        }

        pub struct PaymentService {
            pub gateway: PaymentGateway,
        }

        impl PaymentService {
            pub fn charge(&self) {
                self.gateway.authorize();
                PaymentService::log();
            }

            pub fn log() {}
        }
        """

        let artifact = parser.parse(source: source, fileName: "payments.rs")
        let service = artifact.types.first { $0.name == "PaymentService" }
        let charge = service?.members.first { $0.name == "charge" }

        #expect(charge?.callSites.contains {
            $0.receiverType == "PaymentGateway" && $0.methodName == "authorize"
        } == true)
        #expect(charge?.callSites.contains {
            $0.receiverType == "PaymentService" && $0.methodName == "log"
        } == true)
    }

    @Test func enumAssignmentsDriveStateAnalysis() throws {
        let source = """
        pub enum DownloadState {
            Requested,
            Downloading,
            Finished,
        }

        pub struct Download {
            pub state: DownloadState,
        }

        impl Download {
            pub fn run(&mut self) {
                self.state = DownloadState::Requested;
                self.state = DownloadState::Downloading;
                self.state = DownloadState::Finished;
            }
        }
        """

        let artifact = parser.parse(source: source, fileName: "download.rs")
        let download = artifact.types.first { $0.name == "Download" }
        let run = download?.members.first { $0.name == "run" }

        #expect(run?.assignments.map(\.targetName) == ["state", "state", "state"])
        #expect(run?.assignments.map(\.value.text) == ["Requested", "Downloading", "Finished"])

        let diagram = try StateDiagramBuilder(
            configuration: .init(typeName: "Download", variableName: "state")
        ).build(from: artifact)
        #expect(diagram.transitions.count == 3)
    }

    @Test func sequenceDiagramIsResolvedFromRustCallSites() {
        let source = """
        pub struct PaymentGateway;

        impl PaymentGateway {
            pub fn authorize(&self) {}
        }

        pub struct PaymentService {
            pub gateway: PaymentGateway,
        }

        impl PaymentService {
            pub fn charge(&self) {
                self.gateway.authorize();
            }
        }

        pub struct Checkout {
            pub payment: PaymentService,
        }

        impl Checkout {
            pub fn place_order(&self) {
                self.payment.charge();
            }
        }
        """

        let artifact = parser.parse(source: source, fileName: "checkout.rs")
        let diagram = SequenceDiagramBuilder(entryPoint: ("Checkout", "place_order")).build(from: artifact)
        #expect(diagram.messages.contains {
            $0.from == "Checkout" && $0.to == "PaymentService" && $0.label == "charge"
        })
        #expect(diagram.messages.contains {
            $0.from == "PaymentService" && $0.to == "PaymentGateway" && $0.label == "authorize"
        })
    }
}
