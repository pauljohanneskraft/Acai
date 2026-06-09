import SwiftUI

extension View {
    @ViewBuilder
    func `if`<Then: View, Else: View>(
        _ condition: Bool,
        @ViewBuilder then thenContent: (Self) -> Then,
        @ViewBuilder else elseContent: (Self) -> Else
    ) -> some View {
        if condition {
            thenContent(self)
        } else {
            elseContent(self)
        }
    }

    @ViewBuilder
    func `if`<Then: View>(
        _ condition: Bool,
        @ViewBuilder then thenContent: (Self) -> Then
    ) -> some View {
        if condition {
            thenContent(self)
        } else {
            self
        }
    }
}
