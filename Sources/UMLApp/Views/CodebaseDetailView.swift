import SwiftUI

struct CodebaseDetailView: View {
    let codebase: Codebase
    @EnvironmentObject private var model: ProjectBrowserViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "folder")
                VStack(alignment: .leading) {
                    Text(codebase.name).font(.title2).bold()
                    Text(codebase.directoryPath).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await model.reindex(codebaseID: codebase.id) } } label: { Label("Reindex", systemImage: "arrow.clockwise") }
                Button {
                    model.selection = .diagram(codebase.id)
                } label: {
                    Label("View Diagram", systemImage: "rectangle.3.group")
                }
                .disabled(codebase.artifact == nil)
                Button { model.exportDOT(for: codebase.id) } label: { Label("Export DOT", systemImage: "square.and.arrow.up") }
            }
            Divider()
            Text("Analysis summary").font(.headline)
            if let artifact = codebase.artifact {
                HStack {
                    Text("Types")
                    Spacer()
                    Text("\(artifact.types.count)").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Relationships")
                    Spacer()
                    Text("\(artifact.relationships.count)").foregroundStyle(.secondary)
                }
            } else {
                Text("No analysis cached. Reindex to parse the codebase.").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }
}
