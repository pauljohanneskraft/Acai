import Foundation

extension LocalizedStringResource {
    /// A stable identifier whose English, German and French text lives in
    /// `Resources/Localizable.xcstrings`. Binding the bundle is required: `AcaiApp` is a package
    /// library, so a bare `LocalizedStringKey` would look in `Bundle.main` — the app bundle.
    static func app(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, table: "Localizable", bundle: .atURL(Bundle.module.bundleURL))
    }
}
