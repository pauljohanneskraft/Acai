import SwiftUI
import AcaiCore

struct CodebaseGlobalsSection: View {
    let codebase: Codebase
    let artifact: CodeArtifact

    var body: some View {
        CollapsibleSection(
            title: .app("View.CodebaseGlobalsSection.GlobalVariablesConstants"),
            defaultExpanded: false
        ) {
            SectionCountBadge(text: .app("View.SectionCountBadge.Count \(artifact.globalVariables.count)"))
        } content: {
            let sortedGlobals = artifact.globalVariables.sorted(byLocalizedName: \.name)
            LazyVStack(spacing: Spacing.xxs) {
                ForEach(Array(sortedGlobals.enumerated()), id: \.offset) { _, global in
                    globalRow(global: global)
                }
            }
        }
    }

    private func isConstant(_ global: Member) -> Bool {
        global.modifiers.contains(.const) || global.modifiers.contains(.readonly)
    }

    private func globalRow(global: Member) -> some View {
        HStack(spacing: Spacing.s) {
            kindBadge(global)
            Text(verbatim: global.name)
                .fontWeight(.medium)
            if let type = global.type {
                Text(.app("View.CodebaseGlobalsSection.TypeAnnotation \(type.name)"))
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
        .revealsInFinder(codebase: codebase, relativePath: global.location?.filePath)
        .padding(.horizontal)
        .padding(.vertical, Spacing.xs)
    }

    private func kindBadge(_ global: Member) -> some View {
        Text(verbatim: isConstant(global) ? "k" : "=")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(isConstant(global) ? Color.teal : Color.indigo)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func tagBadge(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

}
