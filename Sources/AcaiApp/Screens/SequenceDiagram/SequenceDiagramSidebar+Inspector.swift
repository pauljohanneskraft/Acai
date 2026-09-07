import SwiftUI
import AcaiDiagram

// Selection Inspector for `SequenceDiagramSidebar`, kept in its own file only to stay under
// that file's own line-count limit — same pattern used throughout this app (e.g.
// `ProjectBrowserDiagramEditors+GitHubSync.swift`).
extension SequenceDiagramSidebar {
    @ViewBuilder
    var selectionInspector: some View {
        if let messageID = viewModel.selectedMessageID, viewModel.orderedMessages.indices.contains(messageID) {
            messageDetail(viewModel.orderedMessages[messageID])
        } else if let participantID = viewModel.selectedNodeIDs.first, viewModel.selectedNodeIDs.count == 1 {
            participantDetail(participantID)
        } else if viewModel.selectedNodeIDs.count > 1 {
            multiSelectionList
        } else {
            emptyInspectorState
        }
    }

    var emptyInspectorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "cursorarrow.click")
                .font(.title)
                .foregroundStyle(.secondary)
            Text(.app("View.SequenceDiagramSidebar.SelectLifelineMessageInspect"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func participantDetail(_ participantID: String) -> some View {
        let name = viewModel.participantName(participantID) ?? participantID
        let sent = viewModel.orderedMessages.filter { $0.from == participantID }
        let received = viewModel.orderedMessages.filter { $0.to == participantID && $0.from != participantID }
        return List {
            Section(name) {
                if !sent.isEmpty {
                    DisclosureGroup {
                        ForEach(Array(sent.enumerated()), id: \.offset) { _, message in
                            messageRow(message)
                        }
                    } label: {
                        Text(.app("View.SequenceDiagramSidebar.Sends \(sent.count)"))
                    }
                }
                if !received.isEmpty {
                    DisclosureGroup {
                        ForEach(Array(received.enumerated()), id: \.offset) { _, message in
                            messageRow(message)
                        }
                    } label: {
                        Text(.app("View.SequenceDiagramSidebar.Receives \(received.count)"))
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    func messageRow(_ message: SequenceDiagram.Message) -> some View {
        HStack {
            Text(verbatim: message.label ?? message.kind.rawValue)
                .font(.caption.monospaced())
            Spacer()
            Text(verbatim: "\(viewModel.participantName(message.from) ?? message.from) → "
                 + "\(viewModel.participantName(message.to) ?? message.to)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    func messageDetail(_ message: SequenceDiagram.Message) -> some View {
        List {
            Section {
                LabeledContent {
                    Text(verbatim: viewModel.participantName(message.from) ?? message.from)
                } label: {
                    Text(.app("View.SequenceDiagramSidebar.From"))
                }
                LabeledContent {
                    Text(verbatim: viewModel.participantName(message.to) ?? message.to)
                } label: {
                    Text(.app("View.SequenceDiagramSidebar.To"))
                }
                LabeledContent {
                    Text(verbatim: message.kind.rawValue)
                } label: {
                    Text(.app("View.SequenceDiagramSidebar.Kind"))
                }
                LabeledContent {
                    Text(message.order, format: .number)
                } label: {
                    Text(.app("View.SequenceDiagramSidebar.Order"))
                }
            } header: {
                message.label.map { Text(verbatim: $0) }
                    ?? Text(.app("View.SequenceDiagramSidebar.Message"))
            }
        }
        .listStyle(.inset)
    }

    struct SelectableLifeline: Identifiable {
        let id: String
        let name: String
    }

    var multiSelectionList: some View {
        let selected = viewModel.selectedNodeIDs.sorted()
            .map { SelectableLifeline(id: $0, name: viewModel.participantName($0) ?? $0) }
        return MultiSelectionInspector(
            items: selected,
            title: { Text(.app("View.SequenceDiagramSidebar.LifelineInflectTrueSelected \($0)")) },
            rowIcon: { _ in nil },
            rowLabel: \.name,
            rowDetail: nil,
            onSelect: { viewModel.selectNode($0, extending: false) },
            bulkAction: nil
        )
    }
}
