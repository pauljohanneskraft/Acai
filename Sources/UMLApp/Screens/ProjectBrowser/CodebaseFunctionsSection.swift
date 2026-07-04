import SwiftUI
import UMLCore

/// Section view displaying a codebase's top-level (module-scope) functions — the ones that
/// aren't members of any type, so they never show up in the class diagram or the types list.
/// Common in languages with free functions (Python, JavaScript, Dart, Kotlin).
struct CodebaseFunctionsSection: View {
    let codebase: Codebase
    let artifact: CodeArtifact

    var body: some View {
        CollapsibleSection(title: "Top-Level Functions (\(artifact.freestandingFunctions.count))") {
            let sortedFunctions = artifact.freestandingFunctions
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            LazyVStack(spacing: 1) {
                ForEach(Array(sortedFunctions.enumerated()), id: \.offset) { _, function in
                    functionRow(function: function)
                }
            }
        }
    }

    private func signature(for function: Member) -> String {
        let params = function.parameters.map { param in
            param.type.map { "\(param.internalName): \($0.name)" } ?? param.internalName
        }.joined(separator: ", ")
        let returnType = function.type.map { ": \($0.name)" } ?? ""
        return "(\(params))\(returnType)"
    }

    private func functionRow(function: Member) -> some View {
        HStack(spacing: 8) {
            Text("ƒ")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.indigo)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(function.name)
                .fontWeight(.medium)
            Text(signature(for: function))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(function.accessLevel.rawValue)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        #if os(macOS)
        .onTapGesture {
            guard let filePath = function.location?.filePath else {
                print("Unknown location of function: \(function.name)")
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
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}
