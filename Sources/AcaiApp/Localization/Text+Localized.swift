import SwiftUI

extension Text {
    /// A `Text` over an already-localized resource. The plain resource overload renders the same thing
    /// but reads exactly like the plain-string one — this spelling says which of the two it is, and
    /// `LocalizationCatalogTests` holds every `Text` to saying so.
    init(localized resource: LocalizedStringResource) {
        self.init(resource)
    }
}
