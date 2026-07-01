import Testing
@testable import UMLCLI
import UMLDiagram

/// Unit tests for the pure `--state-from` parser (Support/StateVariableSpec.swift).
@Suite("State Variable Spec")
struct StateVariableSpecTests {

    @Test func parsesTypeAndVariable() throws {
        let config = try StateDiagramConfiguration(stateFrom: "Loader.state", maxStates: 12)
        #expect(config.typeName == "Loader")
        #expect(config.variableName == "state")
        #expect(config.maxStates == 12)
    }

    @Test func splitsOnLastDotForNamespacedTypes() throws {
        let config = try StateDiagramConfiguration(stateFrom: "shop.Cart.state", maxStates: 20)
        #expect(config.typeName == "shop.Cart")
        #expect(config.variableName == "state")
    }

    @Test func singleSegmentIsGlobal() throws {
        let config = try StateDiagramConfiguration(stateFrom: "mode", maxStates: 20)
        #expect(config.typeName == nil)
        #expect(config.variableName == "mode")
    }

    @Test func trimsSurroundingWhitespace() throws {
        let config = try StateDiagramConfiguration(stateFrom: "  Loader.state  ", maxStates: 20)
        #expect(config.typeName == "Loader")
        #expect(config.variableName == "state")
    }

    @Test func emptyValueThrows() {
        expectThrows(from: "   ")
    }

    @Test func missingTypeThrows() {
        expectThrows(from: ".state")
    }

    @Test func missingVariableThrows() {
        expectThrows(from: "Loader.")
    }

    private func expectThrows(from value: String) {
        #expect {
            _ = try StateDiagramConfiguration(stateFrom: value, maxStates: 20)
        } throws: { error in
            "\(error)".contains("--state-from must be")
        }
    }
}
