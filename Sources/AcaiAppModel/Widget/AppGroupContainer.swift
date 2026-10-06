import Foundation

/// Must match the `com.apple.security.application-groups` entitlement of the app and the widget extension.
public struct AppGroupContainer: Sendable {
    public static let standard = AppGroupContainer(identifier: "group.de.kraftsoftware.Acai")

    public let identifier: String

    public init(identifier: String) {
        self.identifier = identifier
    }

    /// `nil` without the App Group entitlement, and always off Apple platforms.
    public var url: URL? {
        #if canImport(Darwin)
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        #else
        nil
        #endif
    }
}
