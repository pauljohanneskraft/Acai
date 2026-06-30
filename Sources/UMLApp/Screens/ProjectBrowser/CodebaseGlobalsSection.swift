import SwiftUI
import UMLCore

/// Section view displaying a codebase's top-level (module-scope) variables and constants — globals
/// that, like top-level functions, belong to no type and so never appear in the type list or diagrams.
struct CodebaseGlobalsSection: View {
    let codebase: Codebase
    let artifact: CodeArtifact

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Global Variables & Constants (\(artifact.globalVariables.count))")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 12)

            let sortedGlobals = artifact.globalVariables
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            LazyVStack(spacing: 1) {
                ForEach(Array(sortedGlobals.enumerated()), id: \.offset) { _, global in
                    globalRow(global: global)
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func isConstant(_ global: Member) -> Bool {
        global.modifiers.contains(.const) || global.modifiers.contains(.readonly)
    }

    private func globalRow(global: Member) -> some View {
        HStack(spacing: 8) {
            kindBadge(global)
            Text(global.name)
                .fontWeight(.medium)
            if let type = global.type {
                Text(": \(type.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if isConstant(global) {
                tagBadge("const")
            }
            tagBadge(global.accessLevel.rawValue)
        }
        #if os(macOS)
        .onTapGesture { reveal(global) }
        #endif
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private func kindBadge(_ global: Member) -> some View {
        Text(isConstant(global) ? "k" : "=")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(isConstant(global) ? Color.teal : Color.indigo)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func tagBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    #if os(macOS)
    private func reveal(_ global: Member) {
        guard let filePath = global.location?.filePath else {
            print("Unknown location of global: \(global.name)")
            return
        }
        let url = URL(filePath: codebase.directoryPath).appending(path: filePath)
        guard FileManager.default.fileExists(atPath: url.path()) else {
            print("File doesn't exist at path: \(url.absoluteString)")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    #endif
}
