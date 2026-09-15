import AppKit
import SwiftUI

struct ActionMenuItem {
    var title: String
    var action: (() -> Void)?
    static var separator: Self { Self(title: "", action: nil) }
}

// A real 30-point button keeps the complete menu trigger clickable. SwiftUI's
// borderless Menu can collapse its native popup to the symbol's text height.
struct ActionMenu: View {
    var label: String
    var identifier: String
    var items: [ActionMenuItem]
    var body: some View {
        NativeActionMenu(label: label, identifier: identifier, items: items)
            .frame(width: 30, height: 30).buttonHover().help(label)
            .accessibilityLabel(label).accessibilityIdentifier(identifier)
    }
}

private struct NativeActionMenu: NSViewRepresentable {
    var label: String
    var identifier: String
    var items: [ActionMenuItem]
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> ActionMenuButton {
        let button = ActionMenuButton()
        button.isBordered = false; button.title = ""
        button.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.contentTintColor = NSColor(Palette.secondary)
        button.target = context.coordinator; button.action = #selector(Coordinator.open(_:))
        return button
    }
    func updateNSView(_ button: ActionMenuButton, context: Context) {
        context.coordinator.parent = self
        button.isEnabled = context.environment.isEnabled
        button.setAccessibilityLabel(label); button.setAccessibilityIdentifier(identifier)
    }
    final class Coordinator: NSObject {
        var parent: NativeActionMenu
        private var selectedAction: (() -> Void)?
        init(_ parent: NativeActionMenu) { self.parent = parent }
        @objc func open(_ button: NSButton) {
            let menu = NSMenu(); menu.autoenablesItems = false
            for (index, entry) in parent.items.enumerated() {
                guard entry.action != nil else { menu.addItem(.separator()); continue }
                let item = NSMenuItem(title: entry.title, action: #selector(choose(_:)), keyEquivalent: "")
                item.target = self; item.tag = index; menu.addItem(item)
            }
            selectedAction = nil
            let y = button.isFlipped ? button.bounds.maxY + 4 : button.bounds.minY - 4
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: button)
            // Start editing only after the menu has fully released its focus.
            if let action = selectedAction { DispatchQueue.main.async(execute: action) }
            selectedAction = nil
        }
        @objc func choose(_ item: NSMenuItem) {
            guard parent.items.indices.contains(item.tag) else { return }
            selectedAction = parent.items[item.tag].action
        }
    }
}

final class ActionMenuButton: NSButton {
    override var intrinsicContentSize: NSSize { NSSize(width: 30, height: 30) }
}
