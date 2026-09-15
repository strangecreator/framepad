import AppKit
import FramepadCore

@MainActor enum GroupInteractionChecks {
    static func run(model: AppModel, output: URL, check: (Bool, String) throws -> Void) async throws {
        let originalPointer = NSEvent.mouseLocation
        defer { HoverChecks.move(to: originalPointer) }
        guard let window = NSApp.windows.first(where: { $0.title == "Framepad" }), let url = model.projectURL,
              case .group(let group) = model.project?.items.first else { throw ProjectError.invalid("Group interaction fixture missing") }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        try await SmokeTest.waitUntil { window.isKeyWindow && NSApp.isActive }
        guard let collection = SmokeTest.descendants(window.contentView).compactMap({ $0 as? NSScrollView }).first(where: { $0.documentView?.isKind(of: NSTextView.self) == false && $0.frame.width < 520 }) else { throw ProjectError.invalid("Collection scroll view missing") }
        model.returnToDraft(clearGroup: true)
        model.requestCollectionScroll(to: group.id, style: .revealIfHidden)
        try await RevisionChecks.pause(600)
        try await SmokeTest.waitUntil { model.collectionViewport.isVisible(group.id) }
        collection.documentView?.scroll(.zero)
        try await RevisionChecks.pause(300)
        guard let header = model.collectionViewport.rows[group.id.uuidString] else { throw ProjectError.invalid("Group header not visible") }
        try await click(in: collection, at: CGPoint(x: header.minX + 80, y: header.minY + 22))
        try check(model.selectedGroupID == group.id && !(window.firstResponder is NSTextView), "Clicking the group title selects the group without editing its name")
        try await click(in: collection, at: CGPoint(x: header.minX + 80, y: header.minY + 22))
        try check(model.selectedGroupID == group.id, "Clicking an already selected group keeps it selected")

        model.returnToDraft(clearGroup: true); try await RevisionChecks.pause()
        let first = group.boxes[0]
        guard let card = model.collectionViewport.rows[first.id.uuidString] else { throw ProjectError.invalid("Group member not visible") }
        try await click(in: collection, at: CGPoint(x: card.midX, y: card.midY))
        try check(model.selectedBoxID == first.id && model.selectedGroupID == nil, "Clicking a vbox inside a group selects only the vbox")
        try await click(in: collection, at: CGPoint(x: card.minX + 5, y: card.midY))
        try check(model.selectedGroupID == group.id && model.selectedBoxID == nil, "Clicking group padding selects the group and restores the draft")

        // Choose the command while the real menu is still tracking, then test
        // focus and typing after the menu releases its window state.
        try menuAction("Change group name", in: window)
        try await RevisionChecks.pause(350)
        guard let nameEditor = window.firstResponder as? NSTextView else { throw ProjectError.invalid("Rename did not focus the group name") }
        try await HoverChecks.checkRenameEditor(window: window, groupID: group.id, check: check)
        nameEditor.selectAll(nil); nameEditor.insertText("Renamed with Return", replacementRange: nameEditor.selectedRange())
        RevisionChecks.key(36, "\r"); try await RevisionChecks.pause(300)
        let saved = try ProjectStore.load(at: url)
        try check(saved.items.first?.id == group.id && groupTitle(saved, group.id) == "Renamed with Return" && !(window.firstResponder is NSTextView), "Group name saves on Return and leaves rename mode")
        try menuAction("Change group name", in: window); try await RevisionChecks.pause(250)
        guard let blurEditor = window.firstResponder as? NSTextView else { throw ProjectError.invalid("Second rename did not focus") }
        blurEditor.selectAll(nil); blurEditor.insertText("Renamed on blur", replacementRange: blurEditor.selectedRange())
        RevisionChecks.key(34, "i", flags: .command); try await RevisionChecks.pause(350)
        try check(groupTitle(try ProjectStore.load(at: url), group.id) == "Renamed on blur" && (window.firstResponder as? NoteTextView)?.role == "vbox-prompt", "Group name saves on blur and keeps focus in the newly selected prompt")

        model.selectBox(first)
        RevisionChecks.key(34, "i", flags: .command); try await RevisionChecks.pause()
        guard let prompt = window.firstResponder as? NoteTextView else { throw ProjectError.invalid("Prompt focus missing") }
        prompt.setSelectedRange(NSRange(location: prompt.string.utf16.count, length: 0))
        let beforeText = model.prompt
        RevisionChecks.key(51, "\u{7F}"); try await RevisionChecks.pause()
        try check(model.project?.box(first.id) != nil && model.prompt == String(beforeText.dropLast()), "Backspace edits text instead of deleting a selected vbox while typing")
        window.makeFirstResponder(nil)
        RevisionChecks.key(51, "\u{7F}"); try await RevisionChecks.pause()
        try check(model.project?.box(first.id) == nil && model.project?.groupCount == 1, "Backspace deletes the selected vbox but keeps its group")
        model.undo(); try await RevisionChecks.pause()
        try check(model.project?.box(first.id) != nil, "Backspace deletion is undoable")
        model.selectGroup(group.id, toggle: false)
        let groupOnly = model.project!.items
        RevisionChecks.key(51, "\u{7F}"); try await RevisionChecks.pause()
        try check(model.project?.items == groupOnly, "Backspace never deletes a selected group")

        model.selectBox(model.project!.box(first.id)!)
        let beforeDelete = model.project!.items
        let undoCount = model.undoHistory.count
        try menuAction("Remove group with all vboxes", in: window); try await RevisionChecks.pause(350)
        try check(model.boxCount == 0 && model.project?.groupCount == 0 && model.selectedBoxID == nil && model.selectedGroupID == nil, "Group menu removes the group and all its vboxes, clearing stale selections")
        try check(model.undoHistory.count == undoCount + 1, "Removing a group and its vboxes is a single undo operation")
        model.undo(); try await RevisionChecks.pause(350)
        try check(model.project?.items == beforeDelete && model.selectedBoxID == first.id, "One undo restores the entire group, its order, descriptions, and selected vbox")
        _ = model.flush()
        try check(try ProjectStore.load(at: url).items == beforeDelete, "Restored group and all vboxes persist to disk")

        model.requestCollectionScroll(to: group.boxes[20].id); try await RevisionChecks.pause(600)
        try await HoverChecks.run(window: window, output: output, check: check)
        try await HoverChecks.checkCollection(model: model, window: window, output: output, check: check)
        AppDelegate.snapshot(path: output.appendingPathComponent("scroll-to-end.png").path)
        guard let jump = accessibilityElements(window).first(where: { $0.accessibilityIdentifier() == "collection-scroll-to-bottom" }) else { throw ProjectError.invalid("Scroll-to-end button not found when scrolled up") }
        try check(jump.accessibilityPerformPress(), "Scroll-to-end button is accessible and clickable")
        try await RevisionChecks.pause(650)
        let viewport = model.collectionViewport
        try check((viewport.contentBottom ?? .infinity) - viewport.bounds.maxY < 2, "Scroll-to-end button reaches the bottom of the collection (remaining: \((viewport.contentBottom ?? .infinity) - viewport.bounds.maxY) points)")
        try check(!accessibilityElements(window).contains { $0.accessibilityIdentifier() == "collection-scroll-to-bottom" }, "Scroll-to-end button disappears at the bottom")

        // Move the actual pointer over the progress surface and back out.
        guard let track = SmokeTest.descendants(window.contentView).compactMap({ $0 as? PointerTrackingView }).first(where: { $0.onMove != nil && $0.bounds.width > 500 && $0.bounds.height < 30 }) else { throw ProjectError.invalid("Timeline hover surface missing") }
        let position = model.video.position
        let point = track.convert(CGPoint(x: track.bounds.width * 0.5, y: track.bounds.midY), to: nil)
        HoverChecks.move(to: window.convertPoint(toScreen: point))
        try await RevisionChecks.pause()
        try check(NSCursor.current == .pointingHand, "Progress bar hover sets the pointing-hand cursor")
        try check(model.video.position == position, "Hovering the progress bar leaves the playhead unchanged")
        let popup = accessibilityElements(window).first { $0.accessibilityIdentifier() == "video-hover-time" }
        try check(popup != nil, "Hovering the timeline exposes a time preview")
        AppDelegate.snapshot(path: output.appendingPathComponent("timeline-hover.png").path)
        HoverChecks.move(to: CGPoint(x: window.frame.midX, y: window.frame.maxY - 50)); try await RevisionChecks.pause()
        try check(!accessibilityElements(window).contains { $0.accessibilityIdentifier() == "video-hover-time" }, "Timeline time preview disappears when the pointer leaves")
        model.requestCollectionScroll(to: group.boxes[1].id); try await RevisionChecks.pause(550)
        AppDelegate.snapshot(path: output.appendingPathComponent("group-controls.png").path)
    }

    static func groupTitle(_ project: Project, _ id: UUID) -> String? {
        project.items.compactMap { if case .group(let group) = $0, group.id == id { return group.title }; return nil }.first
    }
    static func menuAction(_ title: String, in window: NSWindow) throws {
        for popup in SmokeTest.descendants(window.contentView).compactMap({ $0 as? ActionMenuButton }) {
            let capture = MenuCapture()
            let observer = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { notification in
                MainActor.assumeIsolated { capture.menu = notification.object as? NSMenu }
            }
            let timer = Timer(timeInterval: 0.25, repeats: true) { _ in
                MainActor.assumeIsolated {
                    guard let menu = capture.menu else { return }
                    if let index = menu.items.firstIndex(where: { $0.title == title }), !capture.invoked {
                        capture.invoked = true; menu.performActionForItem(at: index)
                    }
                    menu.cancelTrackingWithoutAnimation()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            popup.performClick(nil)
            timer.invalidate(); NotificationCenter.default.removeObserver(observer)
            if capture.invoked { return }
        }
        throw ProjectError.invalid("Group menu action not found: \(title)")
    }
    @MainActor private final class MenuCapture { var menu: NSMenu?; var invoked = false }
    struct AccessibilityNode {
        let object: AnyObject
        func accessibilityIdentifier() -> String? { object.accessibilityIdentifier?() ?? nil }
        func accessibilityPerformPress() -> Bool { object.accessibilityPerformPress?() ?? false }
    }
    static func accessibilityElements(_ root: Any, depth: Int = 0) -> [AccessibilityNode] {
        guard depth < 30, let object = root as? NSObject else { return [] }
        let dynamic: AnyObject = object
        let children = (dynamic.accessibilityChildren?() ?? nil) ?? []
        return [AccessibilityNode(object: object)] + children.flatMap { accessibilityElements($0, depth: depth + 1) }
    }
    static func click(in view: NSView, at point: CGPoint) async throws {
        let local = CGPoint(x: point.x, y: view.isFlipped ? point.y : view.bounds.height - point.y)
        let position = view.convert(local, to: nil)
        HoverChecks.move(to: view.window!.convertPoint(toScreen: position))
        try await RevisionChecks.pause(80)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: position, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: view.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { NSApp.postEvent(event, atStart: false) }
            try await RevisionChecks.pause(50)
        }
        try await RevisionChecks.pause(200)
    }
}
