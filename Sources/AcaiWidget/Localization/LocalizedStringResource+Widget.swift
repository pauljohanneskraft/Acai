import SwiftUI

extension LocalizedStringResource {
    /// Binds `Bundle.module`, as `AcaiApp`'s `.app(_:)` does; a bare key would look in the extension's own bundle.
    static func widget(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, table: "Localizable", bundle: .atURL(Bundle.module.bundleURL))
    }
}

extension Text {
    /// For a string that interpolates another `Text`, such as a live relative date; its key carries `%@`.
    init(widget key: LocalizedStringKey) {
        self.init(key, tableName: "Localizable", bundle: .module)
    }
}
