import SwiftUI

struct CodebaseDetailView: View {
    let codebase: Codebase
    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var showingDOT = false
    
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
                Button { showingDOT = true } label: { Label("Generate DOT", systemImage: "doc.plaintext") }
                Button { model.exportDOT(for: codebase.id) } label: { Label("Export", systemImage: "square.and.arrow.up") }
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
        .sheet(isPresented: $showingDOT) {
            let dot = model.generateDOT(for: codebase.id)
            DOTDiagramView(dotText: dot)
                .frame(minWidth: 600, minHeight: 400)
        }
    }
}

