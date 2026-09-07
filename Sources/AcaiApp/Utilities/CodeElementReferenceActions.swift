import SwiftUI
import AcaiCore
import AcaiDiagram

/// Wires `CodeElementReference` resolution into a row: every diagram type that can meaningfully
/// show `reference` becomes a **context-menu action** (macOS/iPad right-click, iPhone long-press)
/// *and* the row's **default tap-through action** (jumping to an already-open diagram that already
/// contains the element, or creating one pre-scoped) — an "Open in…" action.
///
/// Finder reveal is an **additional**, macOS-only secondary item in the same context menu
/// (`FinderReveal`), since some Mac users still want to jump into their real editor from there.
struct CodeElementReferenceActions: ViewModifier {
    /// `nil` when nothing resolvable was found (e.g. a health-check parse diagnostic, which carries
    /// no type/method identity) — this becomes a no-op passthrough for the "Open in…" part.
    let reference: CodeElementReference?
    /// `nil` when there's no codebase context to resolve against (e.g. the quality rules editor's
    /// live preview) — makes this whole modifier a passthrough.
    let codebase: Codebase?
    /// `nil` for e.g. a relationship spanning two files.
    var relativePath: String?

    @EnvironmentObject private var model: ProjectBrowserViewModel

    private var resolutions: [CodeElementResolution] {
        guard let reference, let codebase, let artifact = model.artifact(for: codebase.id) else { return [] }
        let scoped = model.store.generatedDiagrams.values.filter { $0.codebaseID == codebase.id }
        return reference.resolutions(in: artifact, existingDiagrams: Array(scoped))
    }

    private var finderReveal: FinderReveal {
        FinderReveal(
            codebase: codebase, relativePath: relativePath,
            onFailure: { [store = model.store] in
                store.report(.app("Error.FinderReveal.Failed \($0.localizedDescription)"))
            }
        )
    }

    func body(content: Content) -> some View {
        let resolutions = resolutions
        Group {
            if let first = resolutions.first {
                Button {
                    open(first)
                } label: {
                    content.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
        .contextMenu {
            ForEach(resolutions) { resolution in
                Button {
                    open(resolution)
                } label: {
                    let diagram = String(localized: resolution.diagramType.title)
                    Label(
                        .app("View.CodeElementReferenceActions.OpenIn \(diagram)"),
                        systemImage: resolution.diagramType.systemImage)
                }
            }
            #if os(macOS)
            if finderReveal.isAvailable {
                if !resolutions.isEmpty { Divider() }
                Button {
                    finderReveal.reveal()
                } label: {
                    Label(.app("View.CodeElementReferenceActions.RevealFinder"), systemImage: "folder")
                }
            }
            #endif
        }
    }

    private func open(_ resolution: CodeElementResolution) {
        guard let codebase else { return }
        switch resolution.target {
        case .existing(let id):
            model.selection = .generatedDiagram(id)
        case .create(let content):
            guard let projectID = model.projectID(for: codebase.id) else { return }
            if let id = model.diagrams.add(to: projectID, codebaseID: codebase.id, content: content) {
                model.selection = .generatedDiagram(id)
            }
        }
    }
}

extension View {
    /// A no-op passthrough when `reference` or `codebase` is `nil`.
    func openInCodeElement(
        _ reference: CodeElementReference?, codebase: Codebase?, relativePath: String? = nil
    ) -> some View {
        modifier(CodeElementReferenceActions(reference: reference, codebase: codebase, relativePath: relativePath))
    }
}
