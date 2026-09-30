/// A TOML reader scoped to what `pyproject.toml`'s package-layout tables need: table headers,
/// arrays of tables, dotted keys, strings, arrays and inline tables. It exists instead of a
/// dependency because that is the whole of what is read here — see issue #340.
struct TOMLReader: Sendable {
    private enum Step: Equatable {
        case key(String)
        case lastElement
    }

    private let source: String

    init(_ source: String) {
        self.source = source
    }

    func parse() throws -> TOMLValue {
        var scanner = TOMLScanner(source)
        var document = TOMLValue.table([:])
        var current: [Step] = []
        while let statement = try scanner.nextStatement() {
            switch statement {
            case .table(let path):
                current = path.map(Step.key)
                modify(&document, at: current[...]) { value in
                    if value.tableValue == nil { value = .table([:]) }
                }
            case .arrayTable(let path):
                let base = path.map(Step.key)
                modify(&document, at: base[...]) { value in
                    value = .array((value.arrayValue ?? []) + [.table([:])])
                }
                current = base + [.lastElement]
            case .assignment(let key, let value):
                modify(&document, at: (current + key.map(Step.key))[...]) { $0 = value }
            }
        }
        return document
    }

    /// Applies `apply` to the value at `steps`, creating the tables the path names on the way down.
    private func modify(
        _ container: inout TOMLValue, at steps: ArraySlice<Step>, apply: (inout TOMLValue) -> Void
    ) {
        guard let step = steps.first else {
            apply(&container)
            return
        }
        let rest = steps.dropFirst()
        switch step {
        case .key(let key):
            var table = container.tableValue ?? [:]
            var child = table[key] ?? .table([:])
            modify(&child, at: rest, apply: apply)
            table[key] = child
            container = .table(table)
        case .lastElement:
            var values = container.arrayValue ?? []
            var child = values.popLast() ?? .table([:])
            modify(&child, at: rest, apply: apply)
            values.append(child)
            container = .array(values)
        }
    }
}
