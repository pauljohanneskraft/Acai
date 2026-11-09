import Testing
@testable import AcaiCore
@testable import AcaiDiagram

@Suite("Overload selection")
struct OverloadResolverTests {

    private func parameter(_ label: String?, _ type: String?, default defaultValue: String? = nil) -> Parameter {
        Parameter(
            externalName: label, internalName: label ?? "value",
            type: type.map { TypeReference(name: $0) }, defaultValue: defaultValue)
    }

    private func method(_ name: String, _ parameters: [Parameter]) -> Member {
        Member(name: name, kind: .method, accessLevel: .internal, parameters: parameters)
    }

    private func variadic(_ name: String) -> Member {
        Member(
            name: name, kind: .method, accessLevel: .internal,
            parameters: [Parameter(internalName: "values", type: TypeReference(name: "Int"), isVariadic: true)])
    }

    private func call(_ arguments: [String?]?) -> CallSite {
        CallSite(receiver: .selfDispatch, methodName: "render", arguments: arguments)
    }

    @Test func aLoneCandidateNeedsNoNarrowing() {
        let only = method("render", [parameter("text", "String")])
        #expect(OverloadResolver(candidates: [only]).targets(of: call(nil)) == [only])
        #expect(OverloadResolver(candidates: []).targets(of: call([nil])).isEmpty)
    }

    @Test func arityPicksTheOverloadThatCanAcceptTheCall() {
        let one = method("render", [parameter(nil, "String")])
        let two = method("render", [parameter(nil, "String"), parameter("times", "Int")])
        #expect(OverloadResolver(candidates: [one, two]).targets(of: call([nil])) == [one])
        #expect(OverloadResolver(candidates: [one, two]).targets(of: call([nil, nil])) == [two])
    }

    /// A defaulted parameter may be omitted, so a one-argument call *fits* both overloads — and the
    /// one whose parameter count matches exactly wins, as it does in the languages themselves.
    @Test func anExactParameterCountBeatsOneReachedByOmittingADefault() {
        let one = method("render", [parameter(nil, "String")])
        let two = method("render", [parameter(nil, "String"), parameter("times", "Int", default: "1")])
        #expect(OverloadResolver(candidates: [one, two]).targets(of: call([nil])) == [one])
        #expect(OverloadResolver(candidates: [one, two]).targets(of: call([nil, nil])) == [two])
    }

    /// With no exact match, the defaulted overload is the only one that fits.
    @Test func aDefaultedParameterIsOmittableWhenNoOverloadMatchesExactly() {
        let two = method("render", [parameter(nil, "String"), parameter("times", "Int", default: "1")])
        let three = method("render", [
            parameter(nil, "String"), parameter("times", "Int"), parameter("bold", "Bool")
        ])
        #expect(OverloadResolver(candidates: [two, three]).targets(of: call([nil])) == [two])
    }

    @Test func aVariadicOverloadAcceptsAnyNumberOfArguments() {
        let fixed = method("render", [parameter(nil, "Int"), parameter(nil, "Int")])
        let many = variadic("render")
        #expect(OverloadResolver(candidates: [fixed, many]).targets(of: call([nil, nil, nil])) == [many])
    }

    @Test func labelsDecideBetweenOverloadsOfTheSameArity() {
        let text = method("render", [parameter("text", "String")])
        let image = method("render", [parameter("image", "String")])
        #expect(OverloadResolver(candidates: [text, image]).targets(of: call(["text"])) == [text])
        #expect(OverloadResolver(candidates: [text, image]).targets(of: call(["image"])) == [image])
    }

    // MARK: - Falling back to the name

    @Test func aCallWithNoRecordedArgumentListFallsBackToEveryCandidate() {
        let one = method("render", [parameter(nil, "String")])
        let two = method("render", [parameter(nil, "String"), parameter("times", "Int")])
        #expect(OverloadResolver(candidates: [one, two]).targets(of: call(nil)) == [one, two])
    }

    @Test func anUnlabelledCallBetweenTwoSameArityOverloadsFallsBackToBoth() {
        let text = method("render", [parameter("text", "String")])
        let image = method("render", [parameter("image", "String")])
        #expect(OverloadResolver(candidates: [text, image]).targets(of: call([nil])) == [text, image])
    }

    /// When the recorded arity fits no overload at all, the arity — not the call — is what is
    /// unreliable, so it narrows nothing rather than resolving to nothing.
    @Test func anArityMatchingNoOverloadNarrowsNothing() {
        let one = method("render", [parameter("text", "String")])
        let two = method("render", [parameter("text", "String"), parameter("times", "Int")])
        #expect(OverloadResolver(candidates: [one, two]).targets(of: call([nil, nil, nil])) == [one, two])
    }
}
