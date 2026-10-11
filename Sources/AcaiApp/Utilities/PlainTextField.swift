#if os(macOS)
import AppKit
import SwiftUI

/// Sized from its own font on every pass; a `.plain` `TextField` keeps the height of the font it was first measured at.
struct PlainTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: LocalizedStringResource
    let font: NSFont
    let accessibilityIdentifier: String
    var textColor: NSColor = .controlTextColor

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.font = font
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier(accessibilityIdentifier)
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.text = $text
        var placeholder = placeholder
        placeholder.locale = context.environment.locale
        let placeholderString = String(localized: placeholder)
        if nsView.font != font {
            nsView.font = font
        }
        if nsView.textColor != textColor {
            nsView.textColor = textColor
        }
        if nsView.placeholderString != placeholderString {
            nsView.placeholderString = placeholderString
            nsView.setAccessibilityLabel(placeholderString)
        }
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        CGSize(
            width: proposal.width ?? nsView.cell?.cellSize.width ?? 0,
            height: NSLayoutManager().defaultLineHeight(for: nsView.font ?? font)
        )
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

extension NSFont {
    var bold: NSFont {
        NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask)
    }
}
#endif
