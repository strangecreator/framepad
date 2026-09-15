import AppKit
import CoreGraphics
import FramepadCore

@MainActor enum HoverChecks {
    static func run(window: NSWindow, output: URL, check: (Bool, String) throws -> Void) async throws {
        let originalPointer = CGEvent(source: nil)?.location
        defer { if let originalPointer { movePointer(to: originalPointer) } }
        let elements = GroupInteractionChecks.accessibilityElements(window)
        let targets: [(String, GroupInteractionChecks.AccessibilityNode?)] = [
            ("keyboard", elements.first { $0.object.accessibilityLabel?() == "Keyboard shortcuts" }),
            ("back-to-projects", elements.first { $0.accessibilityIdentifier() == "back-to-projects" }),
            ("create-group", elements.first { $0.accessibilityIdentifier() == "create-group" }),
            ("project-menu", elements.first { $0.accessibilityIdentifier() == "project-actions" }),
            ("save", elements.first { $0.object.accessibilityLabel?() == "Update vbox" }),
            ("scroll-to-end", elements.first { $0.accessibilityIdentifier() == "collection-scroll-to-bottom" })
        ]
        guard let content = window.contentView else { throw ProjectError.invalid("No content view") }
        for (name, target) in targets {
            guard let target, let frame = target.object.accessibilityFrame?(), !frame.isEmpty else { throw ProjectError.invalid("Hover target missing: \(name)") }
            try check(frame.height >= 30, "The \(name) button has a hit area at least 30 points high (\(frame.height))")
            movePointer(to: quartz(CGPoint(x: window.frame.midX, y: window.frame.maxY - 50)))
            try await RevisionChecks.pause(180)
            let rect = content.convert(window.convertFromScreen(frame), from: nil)
            let before = try bitmap(content, rect: rect)
            movePointer(to: quartz(CGPoint(x: frame.midX, y: frame.midY)))
            try await RevisionChecks.pause(250)
            let surfaces = SmokeTest.descendants(content).compactMap { $0 as? PointerTrackingView }.map { view in
                "\(window.convertToScreen(view.convert(view.bounds, to: nil))) visible=\(view.visibleRect) areas=\(view.trackingAreas.count) enabled=\(view.enabled)"
            }.joined(separator: "\n")
            let diagnostic = "Target \(name): \(frame)\nMouse: \(NSEvent.mouseLocation)\nWindow: \(window.frame), key: \(window.isKeyWindow), app active: \(NSApp.isActive)\nCursor: \(NSCursor.current), hand: \(NSCursor.pointingHand)\n\(surfaces)\n"
            try diagnostic.write(to: output.appendingPathComponent("hover-\(name).txt"), atomically: true, encoding: .utf8)
            AppDelegate.snapshot(path: output.appendingPathComponent("hover-\(name).png").path)
            try check(NSCursor.current == .pointingHand, "Real pointer hover shows a hand over the \(name) button")
            let after = try bitmap(content, rect: rect)
            try check(before.representation(using: .png, properties: [:]) != after.representation(using: .png, properties: [:]), "The \(name) button visibly changes on hover")
            if name == "scroll-to-end" {
                let beforeColor = before.colorAt(x: 4, y: before.pixelsHigh / 2)?.usingColorSpace(.sRGB)
                let afterColor = after.colorAt(x: 4, y: after.pixelsHigh / 2)?.usingColorSpace(.sRGB)
                try check((beforeColor?.redComponent ?? 1) < 0.15 && (afterColor?.redComponent ?? 0) > 0.85, "Scroll-to-end button inverts from black to white on hover")
                try check(frame.midX > window.frame.maxX - 100, "Scroll-to-end button sits on the right side of the collection")
                AppDelegate.snapshot(path: output.appendingPathComponent("scroll-to-end-hover.png").path)
            }
        }
        movePointer(to: quartz(CGPoint(x: window.frame.midX, y: window.frame.maxY - 50)))
        try await RevisionChecks.pause(180)
        try check(NSCursor.current == .arrow, "Pointer restores to an arrow outside buttons")
    }
    static func checkRenameEditor(window: NSWindow, groupID: UUID, check: (Bool, String) throws -> Void) async throws {
        let originalPointer = CGEvent(source: nil)?.location
        defer { if let originalPointer { movePointer(to: originalPointer) } }
        guard let field = GroupInteractionChecks.accessibilityElements(window).first(where: { $0.accessibilityIdentifier() == "group-name-\(groupID)" }),
              let frame = field.object.accessibilityFrame?(), let content = window.contentView else { throw ProjectError.invalid("Group name field missing") }
        move(to: CGPoint(x: frame.midX, y: frame.midY)); try await RevisionChecks.pause(180)
        try check(NSCursor.current == .iBeam && hovered(in: window).isEmpty, "Group name editor has a text cursor and no button hover highlight")
        let point = content.convert(window.convertPoint(fromScreen: CGPoint(x: frame.midX, y: frame.midY)), from: nil)
        try await GroupInteractionChecks.click(in: content, at: point)
        try check(window.firstResponder is NSTextView, "Clicking inside the group name keeps the rename editor focused")
    }
    static func checkCollection(model: AppModel, window: NSWindow, output: URL, check: (Bool, String) throws -> Void) async throws {
        let originalPointer = CGEvent(source: nil)?.location
        defer { if let originalPointer { movePointer(to: originalPointer) } }
        guard case .group(let group) = model.project?.items.first, let content = window.contentView,
              let collection = SmokeTest.descendants(content).compactMap({ $0 as? NSScrollView }).first(where: { $0.documentView?.isKind(of: NSTextView.self) == false && $0.frame.width < 520 }) else { throw ProjectError.invalid("Hover collection fixture missing") }
        let viewport = window.convertToScreen(collection.contentView.convert(collection.contentView.bounds, to: nil))
        let cards = GroupInteractionChecks.accessibilityElements(window).compactMap { node -> CGRect? in
            guard (node.object.accessibilityLabel?() ?? "").hasPrefix("Vbox,"), let frame = node.object.accessibilityFrame?(), viewport.contains(frame) else { return nil }
            return frame
        }.sorted { $0.midY > $1.midY }
        guard cards.count >= 2 else { throw ProjectError.invalid("Two visible cards required for hover checks") }
        let neutral = CGPoint(x: window.frame.midX, y: window.frame.maxY - 50)
        move(to: neutral); try await RevisionChecks.pause(180)
        let rect = content.convert(window.convertFromScreen(cards[0]), from: nil)
        let before = try bitmap(content, rect: rect).representation(using: .png, properties: [:])
        move(to: CGPoint(x: cards[0].midX, y: cards[0].midY)); try await RevisionChecks.pause(180)
        try check(hovered(in: window).count == 1 && before != bitmap(content, rect: rect).representation(using: .png, properties: [:]), "Hovering a vbox highlights exactly one control")
        move(to: CGPoint(x: cards[1].midX, y: cards[1].midY)); try await RevisionChecks.pause(180)
        try check(hovered(in: window).count == 1 && before == bitmap(content, rect: rect).representation(using: .png, properties: [:]), "Moving between vboxes removes the previous card highlight")
        model.requestCollectionScroll(to: group.boxes[35].id); try await RevisionChecks.pause(650)
        let point = window.mouseLocationOutsideOfEventStream
        let active = hovered(in: window)
        try check(active.count <= 1 && active.allSatisfy { $0.bounds.intersection($0.visibleRect).contains($0.convert(point, from: nil)) }, "Scrolling beneath a stationary pointer leaves no stale card highlights")
        move(to: neutral)
        model.requestCollectionScroll(to: group.boxes[20].id); try await RevisionChecks.pause(650)
        try check(hovered(in: window).isEmpty, "Recycled collection rows have no hover highlights when the pointer is elsewhere")
        AppDelegate.snapshot(path: output.appendingPathComponent("collection-hover-cleared.png").path)
    }
    private static func hovered(in window: NSWindow) -> [PointerTrackingView] {
        SmokeTest.descendants(window.contentView).compactMap { $0 as? PointerTrackingView }.filter { $0.hoverPoint != nil }
    }
    static func move(to cocoaPoint: CGPoint) { movePointer(to: quartz(cocoaPoint)) }
    private static func quartz(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y)
    }
    private static func movePointer(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        // Warping alone does not emit motion. Route the move through the app's
        // normal window event handling, including tracking areas and cursors.
        if let window = NSApp.keyWindow, let event = NSEvent.mouseEvent(with: .mouseMoved, location: window.convertPoint(fromScreen: NSEvent.mouseLocation), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
            NSApp.postEvent(event, atStart: false)
        }
    }
    private static func bitmap(_ view: NSView, rect: CGRect) throws -> NSBitmapImageRep {
        guard let result = view.bitmapImageRepForCachingDisplay(in: rect) else { throw ProjectError.invalid("No button snapshot") }
        view.cacheDisplay(in: rect, to: result); return result
    }
}
