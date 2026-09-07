import SwiftUI
import AcaiCore

struct CodebaseFunctionsSection: View {
    let codebase: Codebase
    let artifact: CodeArtifact

    var body: some View {
        CollapsibleSection(title: .app("View.CodebaseFunctionsSection.TopLevelFunctions"), defaultExpanded: false) {
            SectionCountBadge(text: .app("View.SectionCountBadge.Count \(artifact.freestandingFunctions.count)"))
        } content: {
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
            Text(.app("View.CodebaseFunctionsSection.Ƒ"))
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.indigo)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(verbatim: function.name)
                .fontWeight(.medium)
            Text(verbatim: signature(for: function))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(verbatim: function.accessLevel.rawValue)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .revealsInFinder(codebase: codebase, relativePath: function.location?.filePath)
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}
