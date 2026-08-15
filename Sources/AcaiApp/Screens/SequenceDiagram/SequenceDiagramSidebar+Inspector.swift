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
            Text("Select a lifeline or message to inspect")
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
                    DisclosureGroup("Sends (\(sent.count))") {
                        ForEach(Array(sent.enumerated()), id: \.offset) { _, message in
                            messageRow(message)
                        }
                    }
                }
                if !received.isEmpty {
                    DisclosureGroup("Receives (\(received.count))") {
                        ForEach(Array(received.enumerated()), id: \.offset) { _, message in
                            messageRow(message)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    func messageRow(_ message: SequenceDiagram.Message) -> some View {
        HStack {
            Text(message.label ?? message.kind.rawValue)
                .font(.caption.monospaced())
            Spacer()
            Text("\(viewModel.participantName(message.from) ?? message.from) → "
                 + "\(viewModel.participantName(message.to) ?? message.to)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    func messageDetail(_ message: SequenceDiagram.Message) -> some View {
        List {
            Section(message.label ?? "Message") {
                LabeledContent("From", value: viewModel.participantName(message.from) ?? message.from)
                LabeledContent("To", value: viewModel.participantName(message.to) ?? message.to)
                LabeledContent("Kind", value: message.kind.rawValue)
                LabeledContent("Order", value: "\(message.order)")
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
            title: { Text("^[\($0) Lifeline](inflect: true) Selected") },
            rowIcon: { _ in nil },
            rowLabel: \.name,
            rowDetail: nil,
            onSelect: { viewModel.selectNode($0, extending: false) },
            bulkAction: nil
        )
    }
}
