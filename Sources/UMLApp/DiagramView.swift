import SwiftUI

struct DOTNode: Identifiable, Equatable {
    let id: String
    var label: AttributedString
    var position: CGPoint
}

struct DOTDiagramView: View {
    @State private var nodes: [DOTNode] = []
    @State private var dragOffsets: [String: CGSize] = [:]
    @State private var dragStartPositions: [String: CGPoint] = [:]
    
    let dotText: String
    
    init(dotText: String) {
        self.dotText = dotText
        
        _nodes = State(
            initialValue: {
                let nodeRegex = /^\s*(?<id>\S+)\s*\[\s*label\s*=\s*(?<label>.*?)\s*\];/

                var parsedNodes: [DOTNode] = []
                let lines = dotText.components(separatedBy: .newlines)
                var yOffset: CGFloat = 50

                for line in lines {
                    // Attempt to match the line against our named capture groups
                    if let match = try? nodeRegex.firstMatch(in: line) {
                        print("new match: \(match)")
                        let id = String(match.id)
                        let label = AttributedString(html: String(match.label.dropFirst().dropLast()))
                        
                        let position = CGPoint(x: 100, y: yOffset)
                        yOffset += 80
                                                
                        parsedNodes.append(DOTNode(id: id, label: label, position: position))
                        print("Successfully parsed node: ID=\(id), Label=\(label)")
                    }
                }
                
                return parsedNodes
            }()
        )
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Draw no edges since edges are not supported
                ForEach(nodes) { node in
                    DOTNodeView(node: node)
                        .position(node.position)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if dragStartPositions[node.id] == nil {
                                        dragStartPositions[node.id] = node.position
                                    }
                                    let start = dragStartPositions[node.id] ?? .zero
                                    let newPos = CGPoint(
                                        x: start.x + value.translation.width,
                                        y: start.y + value.translation.height
                                    )
                                    if let index = nodes.firstIndex(where: { $0.id == node.id }) {
                                        nodes[index].position = newPos
                                    }
                                }
                                .onEnded { _ in
                                    dragStartPositions[node.id] = nil
                                }
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.97))
        }
    }
}

fileprivate struct DOTNodeView: View {
    let node: DOTNode
    
    var body: some View {
        Text(node.label)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.7))
            )
            .foregroundColor(.white)
            .shadow(radius: 3)
    }
}

fileprivate extension AttributedString {
    init(html: String) {
        if let data = html.data(using: .utf8),
           let nsAttributedString = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
           ) {
            self = AttributedString(nsAttributedString)
        } else {
            self = AttributedString(html)
        }
    }
}
