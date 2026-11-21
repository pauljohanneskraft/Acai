import AcaiCore
import AcaiTreeSitter

// MARK: - JavaMemberDefaults

/// The modifiers a Java member carries without spelling them, which depend on its enclosing body.
struct JavaMemberDefaults: Sendable {
    static let classBody = JavaMemberDefaults(isInterfaceBody: false)
    /// An `interface` or `@interface` body.
    static let interfaceBody = JavaMemberDefaults(isInterfaceBody: true)

    private let isInterfaceBody: Bool

    func method(_ info: ModifierInfo, hasBody: Bool) -> ModifierInfo {
        let info = promotedToPublic(info)
        guard isInterfaceBody, !hasBody else { return info }
        return adding([.abstract], to: info)
    }

    func field(_ info: ModifierInfo) -> ModifierInfo {
        let info = promotedToPublic(info)
        guard isInterfaceBody else { return info }
        return adding([.static, .final], to: info)
    }

    func nestedType(_ type: TypeDeclaration) -> TypeDeclaration {
        guard isInterfaceBody else { return type }
        var type = type
        if type.accessLevel == .packagePrivate { type.accessLevel = .public }
        if !type.modifiers.contains(.static) { type.modifiers.append(.static) }
        return type
    }

    /// Java has no package-private keyword, so that level means "nothing written"; `private` stays.
    private func promotedToPublic(_ info: ModifierInfo) -> ModifierInfo {
        guard isInterfaceBody, info.accessLevel == .packagePrivate else { return info }
        var info = info
        info.accessLevel = .public
        return info
    }

    private func adding(_ modifiers: [Modifier], to info: ModifierInfo) -> ModifierInfo {
        var info = info
        for modifier in modifiers where !info.modifiers.contains(modifier) {
            info.modifiers.append(modifier)
        }
        return info
    }
}
