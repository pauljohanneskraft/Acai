import SwiftUI

struct ProjectDetailView: View {
    let project: Project
    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var addingCodebase = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: project.iconSystemName)
                VStack(alignment: .leading) {
                    Text(project.title).font(.title2).bold()
                    Text(project.subtitle).foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) { model.removeProject(project.id) } label: { Label("Delete", systemImage: "trash") }
            }
            Divider()
            HStack {
                Text("Codebases").font(.headline)
                Spacer()
                Button { addingCodebase = true } label: { Label("Add Codebase", systemImage: "plus") }
            }
            List {
                ForEach(project.codebases) { codebase in
                    Button {
                        model.selection = .codebase(codebase.id)
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                            VStack(alignment: .leading) {
                                Text(codebase.name)
                                Text(URL(fileURLWithPath: codebase.directoryPath).lastPathComponent).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let date = codebase.lastIndexed { Text(date, style: .date).font(.caption) }
                        }
                    }
                    .contextMenu {
                        Button("Reindex") { Task { await model.reindex(codebaseID: codebase.id) } }
                        Button(role: .destructive) { model.removeCodebase(codebase.id) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
        .padding()
        .sheet(isPresented: $addingCodebase) {
            NewCodebaseSheet(projectID: project.id)
                .environmentObject(model)
        }
    }
}

