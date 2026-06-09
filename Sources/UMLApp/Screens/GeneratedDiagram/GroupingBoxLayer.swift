import SwiftUI
import UMLRender

/// Canvas layer that draws a labelled box behind each group under the active grouping mode.
/// Bound to the live view model; the reusable `GroupingBoxView` it renders lives in `UMLRender`.
struct GroupingBoxLayer: View {
    @ObservedObject var viewModel: GeneratedDiagramViewModel

    var body: some View {
        ForEach(viewModel.groupingBoxes) { box in
            GroupingBoxView(label: box.label)
                .frame(width: box.rect.width, height: box.rect.height)
                .position(x: box.rect.midX, y: box.rect.midY)
        }
    }
}
