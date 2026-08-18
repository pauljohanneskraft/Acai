import SwiftUI
import AcaiRender

struct GroupingBoxLayer: View {
    @ObservedObject var viewModel: ClassDiagramViewModel

    var body: some View {
        ForEach(viewModel.groupingBoxes) { box in
            GroupingBoxView(label: box.label)
                .frame(width: box.rect.width, height: box.rect.height)
                .position(x: box.rect.midX, y: box.rect.midY)
        }
    }
}
