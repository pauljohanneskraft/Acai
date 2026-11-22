import SwiftSyntax
import AcaiCore

/// What a member body's identifiers are checked against to tell an own-field read from anything else.
struct FieldReadScope {
    var propertyMap: [String: String] = [:]
    /// Every parameter and local the body declares; a bare use of one is never a field read.
    var declaredNames: Set<String> = []
    var methodNames: Set<String> = []
    /// Set inside an extension, whose stored properties live in a declaration the parser may not see.
    var defersUnknownNames = false
}

/// A field read the parser resolved against `propertyMap`, or one left for the merged type to resolve.
enum FieldRead {
    case resolved(FieldAccess)
    case deferred(FieldAccess)
}

/// The bodies of a property's accessors, folded into its `Member`.
struct PropertyBodyAnalysis {
    var callSites: [CallSite] = []
    var fieldReads: [FieldAccess] = []
    var deferredFieldReads: [FieldAccess] = []

    func applied(to member: Member) -> Member {
        var copy = member
        if !callSites.isEmpty { copy.callSites = callSites }
        if !fieldReads.isEmpty { copy.fieldReads = fieldReads }
        copy.deferredFieldReads = deferredFieldReads.nonEmpty
        return copy
    }
}

extension Array where Element == FieldAccess {
    var nonEmpty: Self? { isEmpty ? nil : self }
}

extension CallSiteCollector {
    /// Bare identifiers and the member of a `self.x` access both surface as `DeclReferenceExprSyntax`,
    /// so either is recorded with `receiver == nil`; consumers filter by name.
    func fieldRead(from node: DeclReferenceExprSyntax, in scope: FieldReadScope) -> FieldRead? {
        guard case .identifier = node.baseName.tokenKind, let qualification = node.instanceQualification
        else { return nil }
        let name = node.baseName.text
        if qualification == .bare, scope.declaredNames.contains(name) { return nil }
        let access = FieldAccess(name: name, receiver: nil, location: sourceLocations.sourceLocation(of: node))
        if scope.propertyMap[name] != nil { return .resolved(access) }
        let expression = qualification == .bare ? Syntax(node) : node.parent
        if let expression, expression.parent?.as(FunctionCallExprSyntax.self)?.calledExpression.id == expression.id {
            return nil
        }
        return candidate(access, in: scope)
    }

    /// `if let x` / `guard let x` without an initializer reads the property `x` it shadows.
    func fieldRead(from node: OptionalBindingConditionSyntax, in scope: FieldReadScope) -> FieldRead? {
        guard node.initializer == nil, let pattern = node.pattern.as(IdentifierPatternSyntax.self) else { return nil }
        let name = pattern.identifier.text
        let access = FieldAccess(name: name, receiver: nil, location: sourceLocations.sourceLocation(of: pattern))
        return scope.propertyMap[name] != nil ? .resolved(access) : candidate(access, in: scope)
    }

    private func candidate(_ access: FieldAccess, in scope: FieldReadScope) -> FieldRead? {
        guard scope.defersUnknownNames, !scope.methodNames.contains(access.name),
              access.name.first?.isLowercase == true
        else { return nil }
        return .deferred(access)
    }
}

enum InstanceQualification {
    case bare
    case selfQualified
}

extension DeclReferenceExprSyntax {

    /// `x` is bare and `self.x` self-qualified; `other.x`, implicit `.x` and key-path `\.x` are `nil`.
    var instanceQualification: InstanceQualification? {
        if parent?.is(KeyPathPropertyComponentSyntax.self) == true { return nil }
        guard let access = parent?.as(MemberAccessExprSyntax.self), access.declName.id == id
        else { return .bare }
        guard var base = access.base else { return nil }
        if let optional = base.as(OptionalChainingExprSyntax.self) { base = optional.expression }
        if let forced = base.as(ForceUnwrapExprSyntax.self) { base = forced.expression }
        return base.as(DeclReferenceExprSyntax.self)?.baseName.tokenKind == .keyword(.self) ? .selfQualified : nil
    }
}
