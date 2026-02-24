import SwiftUI

struct DOTNode: Identifiable, Equatable {
    let id: String
    var label: String
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
                // Parse nodes from dotText and assign initial positions automatically
                // Initial positions will be centered horizontally and spaced vertically
                var parsedNodes: [DOTNode] = []
                let lines = dotText.components(separatedBy: .newlines)
                var yOffset: CGFloat = 50
                for line in lines {
                    // Match identifier [label="..."];
                    // identifier can be letters, digits, underscores
                    // label is inside the quotes
                    if let match = line.range(of: #"^(\w+)\s*\[\s*label\s*=\s*"(.*?)"\s*\];"#, options: .regularExpression) {
                        let matchedString = String(line[match])
                        // Extract id and label with regex capturing groups
                        if let idRange = matchedString.range(of: #"^\w+"#, options: .regularExpression),
                           let labelRange = matchedString.range(of: #"label\s*=\s*"(.*?)""#, options: .regularExpression) {
                            let id = String(matchedString[idRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            // Extract label content inside quotes
                            let labelMatch = matchedString[labelRange]
                            // labelMatch looks like label="something"
                            let labelStartIndex = labelMatch.firstIndex(of: "\"")!
                            let labelEndIndex = labelMatch.lastIndex(of: "\"")!
                            let label = String(labelMatch[labelMatch.index(after: labelStartIndex)..<labelEndIndex])
                            
                            // Assign an initial position
                            let position = CGPoint(x: 100, y: yOffset)
                            yOffset += 80
                            parsedNodes.append(DOTNode(id: id, label: label, position: position))
                        }
                    }
                }
                
                print("Parsed nodes: \(parsedNodes.count) from \(dotText)")
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
