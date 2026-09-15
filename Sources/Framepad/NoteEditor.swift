import AppKit
import SwiftUI

/// The placeholder uses the same text container, font and paragraph metrics as typed text.
final class NoteTextView: NSTextView {
    var placeholder = "" { didSet { needsDisplay = true } }
    var role = ""
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, let font else { return }
        let origin = textContainerOrigin
        let padding = textContainer?.lineFragmentPadding ?? 0
        let rect = NSRect(x: origin.x + padding, y: origin.y, width: max(0, bounds.width - origin.x * 2 - padding * 2), height: bounds.height)
        (placeholder as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: NSColor(Palette.muted), .paragraphStyle: defaultParagraphStyle ?? NSParagraphStyle.default])
    }
}

struct NoteEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var fontSize: CGFloat = 15
    var role = "vbox-prompt"
    var isEditable = true
    var compact = false
    var onSubmit: (() -> Void)?
    var onEndEditing: (() -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.drawsBackground = false
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let view = NoteTextView(frame: .zero)
        view.isRichText = false; view.importsGraphics = false; view.drawsBackground = false
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.minSize = .zero; view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = NSSize(width: 0, height: compact ? 2 : 6)
        view.textContainer?.lineFragmentPadding = compact ? 0 : 5
        view.font = .systemFont(ofSize: fontSize); view.textColor = NSColor(compact ? Palette.secondary : Palette.text)
        view.insertionPointColor = NSColor(Palette.accent); view.allowsUndo = true
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = compact ? 3 : 5
        view.defaultParagraphStyle = paragraph
        view.typingAttributes = [.font: view.font!, .foregroundColor: view.textColor!, .paragraphStyle: paragraph]
        view.placeholder = placeholder; view.role = role; view.string = text
        view.delegate = context.coordinator; view.setAccessibilityLabel(role == "vbox-prompt" ? "Vbox description" : "Group description")
        scroll.documentView = view
        context.coordinator.textView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NoteTextView else { return }
        view.placeholder = placeholder; view.isEditable = isEditable
        if view.string != text {
            let selection = view.selectedRange()
            view.string = text
            if view.window?.firstResponder === view { view.setSelectedRange(NSRange(location: min(selection.location, text.utf16.count), length: 0)) }
        }
        context.coordinator.reportHeight()
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditor
        weak var textView: NoteTextView?
        var lastHeight: CGFloat = 0
        init(_ parent: NoteEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = textView else { return }
            parent.text = view.string; view.needsDisplay = true; reportHeight()
        }
        func textDidEndEditing(_ notification: Notification) { parent.onEndEditing?() }
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)), let submit = parent.onSubmit,
               NSApp.currentEvent?.modifierFlags.contains(.shift) != true {
                submit(); textView.window?.makeFirstResponder(nil); return true
            }
            return false
        }
        func reportHeight() {
            guard let callback = parent.onHeightChange, let view = textView, let container = view.textContainer, let manager = view.layoutManager else { return }
            manager.ensureLayout(for: container)
            let height = min(160, max(24, ceil(manager.usedRect(for: container).height + view.textContainerInset.height * 2)))
            guard height != lastHeight else { return }; lastHeight = height
            DispatchQueue.main.async { callback(height) }
        }
    }
}
