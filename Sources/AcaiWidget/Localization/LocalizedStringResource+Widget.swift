import Foundation

extension LocalizedStringResource {
    /// A stable identifier whose English, German and French text lives in
    /// `Resources/Localizable.xcstrings`. Binding the bundle is required for the same reason
    /// `AcaiApp`'s `.app(_:)` does it: `AcaiWidget` is a package library, so a bare key would look
    /// in `Bundle.main` — here the widget extension's own bundle.
    static func widget(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, table: "Localizable", bundle: .atURL(Bundle.module.bundleURL))
    }
}
