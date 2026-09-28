import Foundation
import MCP
import Testing
@testable import AcaiLibrary
@testable import AcaiMCP

/// Covers the strictness the CLI gets from ArgumentParser: an enum-valued argument the server does
/// not recognise is an `invalidParams` error, never a silently dropped filter.
@Suite("Enum Arguments")
struct EnumArgumentTests {

    /// Required arguments beyond `path`, so a tool reaches its argument validation at all.
    private func arguments(for toolName: String, path: URL) -> [String: Value] {
        switch toolName {
        case "acai_diff":
            ["pathOld": .string(path.path), "pathNew": .string(path.path)]
        case "acai_dependents", "acai_impact":
            ["path": .string(path.path), "type": .string("Service")]
        default:
            ["path": .string(path.path)]
        }
    }

    /// The `invalidParams` detail from calling `toolName` with `name` set to an unknown value.
    private func rejection(
        of name: String, on toolName: String, in directory: URL, registry: ToolRegistry
    ) async -> String? {
        var values = arguments(for: toolName, path: directory)
        values[name] = .string("no-such-value")
        let error = await #expect(throws: MCPError.self) {
            _ = try await registry.call(name: toolName, arguments: values)
        }
        guard case .invalidParams(let detail) = error else {
            Issue.record("\(toolName).\(name): expected invalidParams, got \(String(describing: error))")
            return nil
        }
        return detail
    }

    /// The acceptance criterion behind the schema being the single source of the accepted values:
    /// every argument the schema advertises an `enum` for rejects a value outside that list, and the
    /// error names the argument, the value received and the accepted values.
    @Test func everyEnumValuedArgumentIsRejectedWhenUnrecognised() async throws {
        try await MCPTestSupport.withTempDirectory { directory in
            try MCPTestSupport.writeSampleSwiftSource(in: directory)
            let registry = MCPTestSupport.testRegistry
            var checked = 0
            for tool in registry.tools where !tool.isDeprecatedAlias {
                let properties = try #require(tool.inputSchema.objectValue?["properties"]?.objectValue)
                for (name, property) in properties.sorted(by: { $0.key < $1.key }) {
                    guard let accepted = property.objectValue?["enum"]?.arrayValue else { continue }
                    checked += 1
                    let detail = await rejection(of: name, on: tool.name, in: directory, registry: registry)
                    let message = try #require(detail)
                    #expect(message.contains("'\(name)'"))
                    #expect(message.contains("no-such-value"))
                    for value in accepted.compactMap(\.stringValue) {
                        #expect(message.contains(value))
                    }
                }
            }
            // Guards the sweep itself: a schema that stopped advertising its enums would pass vacuously.
            #expect(checked >= 7)
        }
    }

    @Test func selectorFacetsAreRejectedRatherThanDroppedAndWidenedToEverything() async throws {
        try await MCPTestSupport.withTempDirectory { directory in
            try MCPTestSupport.writeSampleSwiftSource(in: directory)
            let registry = MCPTestSupport.testRegistry
            for name in ["kind", "minAccess", "memberKind"] {
                let message = try #require(
                    await rejection(of: name, on: "acai_inspect", in: directory, registry: registry))
                #expect(message.contains("must be one of"))
            }
            // A recognised value still filters, so the rejection isn't blanket strictness.
            let value = try await MCPTestSupport.call(
                "acai_inspect", on: registry, path: directory, ["kind": .string("protocol")])
            #expect(value.objectValue?["types"]?.arrayValue?.isEmpty == true)
        }
    }

    @Test func recognisedValuesStillSelectTheirMode() async throws {
        try await MCPTestSupport.withTempDirectory { directory in
            try MCPTestSupport.writeSampleSwiftSource(in: directory)
            let registry = MCPTestSupport.testRegistry
            let deadCode = try await MCPTestSupport.call(
                "acai_callgraph", on: registry, path: directory, ["mode": .string("deadcode")])
            #expect(deadCode.objectValue?["deadCode"] != nil)
            let result = try await MCPTestSupport.callResult(
                "acai_diagram", on: registry, path: directory, ["format": .string("dot")])
            #expect(MCPTestSupport.firstText(result).contains("digraph"))
        }
    }

    @Test func theSchemaEnumListIsTheOptionTypesCases() {
        #expect(EnumArgument<TypeKind>.kind.accepted == TypeKind.allCases.map(\.rawValue))
        #expect(EnumArgument<AccessLevel>.minimumAccess.accepted == AccessLevel.allCases.map(\.rawValue))
        #expect(EnumArgument<MemberKind>.memberKind.accepted == MemberKind.allCases.map(\.rawValue))
        let schema = EnumArgument<CycleScope>.scope.property["scope"]?.objectValue
        #expect(schema?["enum"]?.arrayValue?.compactMap(\.stringValue) == ["modules", "types", "all"])
    }
}
