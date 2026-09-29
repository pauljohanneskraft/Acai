import Foundation
import MCP
import Testing
@testable import AcaiLibrary
@testable import AcaiMCP

@Suite("Enum Arguments")
struct EnumArgumentTests {

    /// Required arguments beyond `path`, so a tool reaches its argument validation at all.
    private func arguments(for toolName: String, path: URL) -> [String: Value] {
        switch toolName {
        case "acai_diff":
            ["pathOld": .string(path.path), "pathNew": .string(path.path)]
        case "acai_dependents":
            ["path": .string(path.path), "type": .string("Service")]
        case "acai_atlas":
            ["path": .string(path.path), "output": .string(path.appendingPathComponent("atlas.pdf").path)]
        default:
            ["path": .string(path.path)]
        }
    }

    private func rejection(
        of name: String, as value: Value, on toolName: String, in directory: URL, registry: ToolRegistry
    ) async -> String? {
        var values = arguments(for: toolName, path: directory)
        values[name] = value
        let error = await #expect(throws: MCPError.self) {
            _ = try await registry.call(name: toolName, arguments: values)
        }
        guard case .invalidParams(let detail) = error else {
            Issue.record("\(toolName).\(name): expected invalidParams, got \(String(describing: error))")
            return nil
        }
        return detail
    }

    /// The accepted values a property advertises, and an unknown value of the property's shape.
    private func enumeration(of property: Value) -> (accepted: [Value], unknown: Value)? {
        let schema = property.objectValue
        if let accepted = schema?["enum"]?.arrayValue {
            return (accepted, .string("no-such-value"))
        }
        if let accepted = schema?["items"]?.objectValue?["enum"]?.arrayValue {
            return (accepted, .array([.string("no-such-value")]))
        }
        return nil
    }

    @Test func everyEnumValuedArgumentIsRejectedWhenUnrecognised() async throws {
        try await MCPTestSupport.withTempDirectory { directory in
            try MCPTestSupport.writeSampleSwiftSource(in: directory)
            let registry = MCPTestSupport.testRegistry
            var checked: Set<String> = []
            for tool in registry.tools where !tool.isDeprecatedAlias {
                let properties = try #require(tool.inputSchema.objectValue?["properties"]?.objectValue)
                for (name, property) in properties.sorted(by: { $0.key < $1.key }) {
                    guard let (accepted, unknown) = enumeration(of: property) else { continue }
                    checked.insert("\(tool.name).\(name)")
                    let detail = await rejection(
                        of: name, as: unknown, on: tool.name, in: directory, registry: registry)
                    let message = try #require(detail)
                    #expect(message.contains("'\(name)'"))
                    #expect(message.contains("no-such-value"))
                    for value in accepted.compactMap(\.stringValue) {
                        #expect(message.contains(value))
                    }
                }
            }
            // Guards the sweep itself: a schema that stopped advertising its enums would pass vacuously.
            #if os(macOS)
            let platformSpecific: Set<String> = [
                "acai_image.theme", "acai_atlas.theme", "acai_hotspots.languages"
            ]
            #else
            let platformSpecific: Set<String> = []
            #endif
            let expected: Set<String> = [
                "acai_inspect.kind", "acai_inspect.memberKind", "acai_callgraph.mode", "acai_quality.scope",
                "acai_diagram.format", "acai_analyze.languages", "acai_diff.languages"
            ]
            #expect(expected.union(platformSpecific).isSubset(of: checked))
        }
    }

    @Test func selectorFacetsAreRejectedRatherThanDroppedAndWidenedToEverything() async throws {
        try await MCPTestSupport.withTempDirectory { directory in
            try MCPTestSupport.writeSampleSwiftSource(in: directory)
            let registry = MCPTestSupport.testRegistry
            for name in ["kind", "minAccess", "memberKind"] {
                let message = try #require(
                    await rejection(
                        of: name, as: .string("no-such-value"), on: "acai_inspect",
                        in: directory, registry: registry))
                #expect(message.contains("must be one of"))
            }
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
        #expect(EnumArgument<ThemeOption>.theme.accepted == ["light", "dark"])
        let schema = EnumArgument<CycleScope>.scope.property["scope"]?.objectValue
        #expect(schema?["enum"]?.arrayValue?.compactMap(\.stringValue) == ["modules", "types", "all"])
    }

    @Test func languagesTypoIsRejectedEvenAlongsideAKnownName() async throws {
        try await MCPTestSupport.withTempDirectory { directory in
            try MCPTestSupport.writeSampleSwiftSource(in: directory)
            let registry = MCPTestSupport.testRegistry
            for languages: Value in [.array([.string("swfit")]), .array([.string("swift"), .string("swfit")])] {
                let message = try #require(
                    await rejection(
                        of: "languages", as: languages, on: "acai_inspect", in: directory, registry: registry))
                #expect(message.contains("'languages'"))
                #expect(message.contains("'swfit'"))
                #expect(message.contains(SourceLanguageResolver().names.joined(separator: ", ")))
            }
            let message = try #require(
                await rejection(
                    of: "languages", as: .string("swift"), on: "acai_inspect", in: directory, registry: registry))
            #expect(message.contains("array of strings"))
        }
    }

    @Test func languagesAcceptsAKnownNameInAnyCase() async throws {
        try await MCPTestSupport.withTempDirectory { directory in
            try MCPTestSupport.writeSampleSwiftSource(in: directory)
            let value = try await MCPTestSupport.call(
                "acai_inspect", on: MCPTestSupport.testRegistry, path: directory,
                ["languages": .array([.string("Swift")])])
            #expect(value.objectValue?["types"]?.arrayValue?.isEmpty == false)
        }
    }

    @Test func theLanguagesSchemaListIsTheResolversNames() throws {
        let names = SourceLanguageResolver().names.map(Value.string)
        for tool in MCPTestSupport.testRegistry.tools where !tool.isDeprecatedAlias {
            let property = tool.inputSchema.objectValue?["properties"]?.objectValue?["languages"]
            let items = try #require(property?.objectValue?["items"]?.objectValue, "\(tool.name)")
            #expect(items["enum"]?.arrayValue == names, "\(tool.name)")
        }
    }

    #if os(macOS)
    @Test func deprecatedDefaultThemeStillRenders() async throws {
        try await MCPTestSupport.withTempDirectory { directory in
            try MCPTestSupport.writeSampleSwiftSource(in: directory)
            let result = try await MCPTestSupport.callResult(
                "acai_image", on: MCPTestSupport.testRegistry, path: directory,
                ["kind": .string("class"), "theme": .string("default")])
            guard case let .image(data, mimeType, _, _) = try #require(result.content.first) else {
                Issue.record("expected image content")
                return
            }
            #expect(mimeType == "image/png")
            #expect(Data(base64Encoded: data)?.isEmpty == false)
        }
    }
    #endif
}
