import AcaiCore
import AcaiTreeSitter

// MARK: - JavaMemberDefaults

/// The modifiers a Java member carries without spelling them, which depends on the body enclosing
/// it. A class body implies nothing. An interface or annotation-type body makes every member
/// `public`, a body-less method `abstract` and a field `static final`.
struct JavaMemberDefaults: Sendable {
    /// A class, record or enum body: every modifier is written out, so the parsed set stands.
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

    /// Java has no `package-private` keyword, so that access level only ever means "no modifier was
    /// written" — which inside an interface means `public`. An explicitly `private` member (a Java 9
    /// private interface method) is left alone.
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
