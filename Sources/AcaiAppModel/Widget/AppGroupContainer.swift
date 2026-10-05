import Foundation

/// The App Group container the app writes widget snapshots into and the widget extension reads
/// them out of. The identifier has to match the `com.apple.security.application-groups` entitlement
/// on both targets, so it is declared once here and shared.
public struct AppGroupContainer: Sendable {
    public static let standard = AppGroupContainer(identifier: "group.de.kraftsoftware.Acai")

    public let identifier: String

    public init(identifier: String) {
        self.identifier = identifier
    }

    /// `nil` when the process holds no App Group entitlement, which is how a build without the
    /// entitlement presents itself rather than by failing — callers fall back to "not shared".
    public var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
