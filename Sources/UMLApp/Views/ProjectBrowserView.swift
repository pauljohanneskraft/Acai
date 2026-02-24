import SwiftUI

struct ProjectBrowserView: View {
    @StateObject private var model = ProjectBrowserViewModel()
    @State private var newProjectPresented = false
    
    var body: some View {
        NavigationSplitView {
            List(selection: Binding {
                switch model.selection {
                case .project(let id): return id
                case .codebase(let id): return id
                case .diagram(let id): return id
                case .none: return nil
                }
            } set: { newValue in
                if let id = newValue as? UUID {
                    if model.store.projects.contains(where: { $0.id == id }) {
                        model.selection = .project(id)
                    } else if model.store.projects.flatMap({ $0.codebases }).contains(where: { $0.id == id }) {
                        model.selection = .codebase(id)
                    }
                }
            }) {
                Section("Projects") {
                    ForEach(model.store.projects) { project in
                        NavigationLink(value: project.id) {
                            Label(project.title, systemImage: project.iconSystemName)
                                .badge(project.codebases.count)
                        }
                        .contextMenu {
                            Button(role: .destructive) { model.removeProject(project.id) } label: { Label("Delete Project", systemImage: "trash") }
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    Button { newProjectPresented = true } label: { Label("New Project", systemImage: "plus") }
                }
            }
        } detail: {
            switch model.selection {
            case .project(let id):
                if let project = model.store.projects.first(where: { $0.id == id }) {
                    ProjectDetailView(project: project)
                        .environmentObject(model)
                } else { Text("Select a project") }
            case .codebase(let id):
                if let codebase = model.store.projects.flatMap({ $0.codebases }).first(where: { $0.id == id }) {
                    CodebaseDetailView(codebase: codebase)
                        .environmentObject(model)
                } else { Text("Select a codebase") }
            case .diagram(let codebaseID):
                if let codebase = model.store.projects.flatMap(\.codebases).first(where: { $0.id == codebaseID }),
                   let artifact = codebase.artifact {
                    ClassDiagramView(artifact: artifact, codebaseName: codebase.name)
                        .environmentObject(model)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No analysis available. Reindex the codebase first.")
                            .foregroundStyle(.secondary)
                    }
                }
            case .none:
                Text("Create or select a project")
            }
        }
        .sheet(isPresented: $newProjectPresented) {
            NewProjectSheet { title, subtitle, icon in
                model.addProject(title: title, subtitle: subtitle, iconSystemName: icon)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .createNewProject)) { _ in
            newProjectPresented = true
        }
    }
}

