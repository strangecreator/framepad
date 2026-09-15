import AppKit
import FramepadCore

@MainActor enum RevisionChecks {
    static func run(model: AppModel, output: URL, check: (Bool, String) throws -> Void) async throws {
        guard let window = NSApp.keyWindow, let originalURL = model.projectURL else { throw ProjectError.invalid("No workspace window") }
        model.returnToDraft(clearGroup: true)
        try await pause()
        guard let editor = SmokeTest.descendants(window.contentView).compactMap({ $0 as? NoteTextView }).first(where: { $0.role == "vbox-prompt" }) else { throw ProjectError.invalid("Prompt editor not found") }
        model.prompt = ""; try await pause()
        AppDelegate.snapshot(path: output.appendingPathComponent("placeholder.png").path)
        model.prompt = "What do you notice?"; try await pause()
        AppDelegate.snapshot(path: output.appendingPathComponent("placeholder-typed.png").path)
        window.makeFirstResponder(editor); model.prompt = "Global controls"; model.video.seek(0.4); model.video.pause()
        try await pause()
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        key(124, "\u{F703}")
        try await pause()
        try check(abs(model.video.position - 0.4) < 0.01 && editor.selectedRange().location == 5, "Right arrow moves the prompt caret without seeking")
        key(123, "\u{F702}"); try await pause()
        try check(abs(model.video.position - 0.4) < 0.01 && editor.selectedRange().location == 4, "Left arrow moves the prompt caret without seeking")
        key(124, "\u{F703}", flags: .command); try await pause()
        try check(abs(model.video.position - 3.4) < 0.01 && editor.selectedRange().location == 4, "Command-Right seeks while typing without moving the prompt caret")
        key(123, "\u{F702}", flags: .command); try await pause()
        try check(abs(model.video.position - 0.4) < 0.01 && editor.selectedRange().location == 4, "Command-Left seeks while typing without moving the prompt caret")
        SmokeTest.postKey(124, "\u{F703}", down: true, flags: .command); try await pause(460)
        SmokeTest.postKey(124, "\u{F703}", down: false, flags: .command); try await pause()
        try check(model.video.position > 6 && editor.selectedRange().location == 4, "Holding Command-Right repeats seeking while typing")
        let releasedPosition = model.video.position; try await pause(300)
        try check(model.video.position == releasedPosition, "Releasing Command-Right stops repeated seeking")
        model.video.seek(0.4)
        key(49, " ", flags: .option); try await pause(250)
        try check(model.video.playing && model.prompt == "Global controls", "Option-Space plays while typing without inserting a character")
        key(49, " ", flags: .option); try await pause()
        try check(!model.video.playing, "Option-Space pauses while typing")
        key(8, "c", flags: [.command, .shift]); try await pause()
        try check(model.cropMode && model.prompt == "Global controls", "Crop shortcut works while typing")
        model.crop = CropRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        key(13, "w", flags: .command); try await pause()
        try check(model.crop == nil && !model.cropMode && window.isVisible && window.firstResponder === editor, "Command-W removes the entire draft crop without closing the window or blurring the prompt")
        window.makeFirstResponder(nil); key(34, "i", flags: .command); try await pause()
        try check(window.firstResponder === editor && model.prompt == "Global controls", "Command-I focuses the prompt without changing its text")
        editor.setSelectedRange(NSRange(location: 4, length: 0)); key(34, "i", flags: .command); try await pause()
        try check(editor.selectedRange().location == 4, "Command-I preserves the caret when the prompt is already focused")

        guard let savedBox = model.project?.boxes.first(where: { $0.crop != nil }) else { throw ProjectError.invalid("Saved crop missing") }
        model.selectBox(savedBox); try await pause()
        guard let surface = SmokeTest.descendants(window.contentView).compactMap({ $0 as? CropInteractionView }).first,
              let rect = surface.selectionRect, let initial = model.crop else { throw ProjectError.invalid("Crop interaction surface missing") }
        try check(!model.cropMode && surface.handle(at: CGPoint(x: rect.maxX, y: rect.midY)) == .right, "Saved vbox crop has active edge handles without redrawing it")
        let edge = CGPoint(x: rect.maxX, y: rect.midY)
        try await drag(surface, from: edge, to: CGPoint(x: edge.x + surface.videoRect.width * 0.1, y: edge.y))
        try check(abs((model.crop?.width ?? 0) - initial.width - 0.1) < 0.005 && model.crop?.x == initial.x, "Mouse drag resizes saved crop edge while preserving its opposite edge")
        guard let resized = model.crop, let resizedRect = surface.selectionRect else { throw ProjectError.invalid("Resized crop missing") }
        try await drag(surface, from: CGPoint(x: resizedRect.midX, y: resizedRect.midY), to: CGPoint(x: resizedRect.midX - surface.videoRect.width * 0.05, y: resizedRect.midY + surface.videoRect.height * 0.05))
        try check(abs((model.crop?.x ?? 0) - resized.x + 0.05) < 0.005 && abs((model.crop?.width ?? 0) - resized.width) < 0.005, "Mouse drag moves a crop without changing its size")
        guard let corner = surface.selectionRect else { throw ProjectError.invalid("Crop corner missing") }
        let beforeCorner = model.crop!
        try await drag(surface, from: CGPoint(x: corner.maxX, y: corner.maxY), to: CGPoint(x: corner.maxX - surface.videoRect.width * 0.04, y: corner.maxY - surface.videoRect.height * 0.04))
        try check(abs(model.crop!.width - beforeCorner.width + 0.04) < 0.005 && abs(model.crop!.height - beforeCorner.height + 0.04) < 0.005, "Corner drag resizes both crop dimensions")
        AppDelegate.snapshot(path: output.appendingPathComponent("editable-crop.png").path)
        let updatedCrop = model.crop
        model.saveBox(); try await SmokeTest.waitUntil { !model.isSaving }
        try check(model.project?.box(savedBox.id)?.crop == updatedCrop, "Saving an edited vbox persists its resized crop")
        window.makeFirstResponder(editor); key(6, "z", flags: .command); try await pause()
        try check(model.project?.box(savedBox.id)?.imageFile == savedBox.imageFile && model.crop == savedBox.crop, "Global undo restores previous captured image and crop overlay")
        key(13, "w", flags: .command); try await pause()
        try check(model.crop == nil && !model.cropMode && surface.selectionRect == nil && model.selectedBoxID == savedBox.id, "Command-W clears a saved vbox crop while keeping the vbox selected")
        key(36, "\r", flags: .command); try await pause()
        try await SmokeTest.waitUntil { !model.isSaving }
        try check(model.project?.box(savedBox.id)?.crop == nil, "Saving after clearing the crop replaces the saved crop with a full frame")
        key(6, "z", flags: .command); try await pause()
        try check(model.crop == savedBox.crop, "Undo restores the crop after saving a full-frame replacement")
        let originalPrompt = model.project!.box(savedBox.id)!.prompt
        model.prompt = "An edit to undo"; try await pause(600)
        key(6, "z", flags: .command); try await pause()
        try check(model.project?.box(savedBox.id)?.prompt == originalPrompt && model.prompt == originalPrompt, "Global undo reverses an autosaved vbox description while focused in its editor")
        model.returnToDraft(clearGroup: true)
        let oldGroup = model.project?.group(containing: savedBox.id)
        let beforeGroups = model.project!.groupCount
        model.createGroup(withBox: savedBox.id)
        let newGroup = model.selectedGroupID!
        try check(model.project?.group(containing: savedBox.id) == newGroup, "Create group with an existing vbox")
        key(6, "z", flags: .command); try await pause()
        try check(model.project?.groupCount == beforeGroups && model.project?.group(containing: savedBox.id) == oldGroup, "One undo reverses create-and-move-to-group as a single operation")

        guard let group = model.project?.items.compactMap({ if case .group(let group) = $0 { return group }; return nil }).first else { throw ProjectError.invalid("Group missing") }
        model.requestCollectionScroll(to: group.boxes.last?.id ?? group.id)
        try await pause(450)
        // Group footer is below the final member, so scroll the collection to its end.
        let scrolls = SmokeTest.descendants(window.contentView).compactMap { $0 as? NSScrollView }
        if let collection = scrolls.first(where: { $0.documentView?.isKind(of: NSTextView.self) == false && $0.frame.width < 520 }) {
            if let document = collection.documentView { document.scroll(CGPoint(x: 0, y: max(0, document.bounds.height - collection.contentSize.height))) }
        }
        try await pause(350)
        guard let description = SmokeTest.descendants(window.contentView).compactMap({ $0 as? NoteTextView }).first(where: { $0.role == "group-\(group.id)" }) else { throw ProjectError.invalid("Group description editor not visible") }
        window.makeFirstResponder(description)
        description.selectAll(nil); description.insertText("Committed group description", replacementRange: description.selectedRange())
        description.setSelectedRange(NSRange(location: 4, length: 0)); model.video.seek(0.4)
        key(124, "\u{F703}"); try await pause()
        try check(abs(model.video.position - 0.4) < 0.01 && description.selectedRange().location == 5, "Bare arrows retain text navigation in group descriptions")
        key(124, "\u{F703}", flags: .command); try await pause()
        try check(abs(model.video.position - 3.4) < 0.01 && description.selectedRange().location == 5, "Command-arrows seek from group descriptions")
        key(34, "i", flags: .command); try await pause()
        try check(window.firstResponder === editor, "Command-I moves focus from the collection description to the prompt")
        window.makeFirstResponder(description)
        key(36, "\r"); try await pause()
        try check(window.firstResponder !== description, "Enter removes group-description input focus")
        let diskProject = try ProjectStore.load(at: originalURL)
        let diskGroup = diskProject.items.compactMap { if case .group(let group) = $0 { return group }; return nil }.first { $0.id == group.id }
        try check(diskGroup?.prompt == "Committed group description", "Enter commits group description to disk without adding a newline")
        key(6, "z", flags: .command); try await pause()
        try check(model.project?.items.compactMap { if case .group(let group) = $0 { return group }; return nil }.first?.prompt == group.prompt, "Group description commit is undoable")

        model.cropMode = true; model.crop = CropRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        window.toggleFullScreen(nil)
        try await SmokeTest.waitUntil { window.styleMask.contains(.fullScreen) }
        try await pause(700)
        key(13, "w", flags: .command); try await pause(250)
        try check(window.styleMask.contains(.fullScreen) && window.isVisible && !model.cropMode && model.crop == nil, "Command-W clears the crop while keeping the window in full screen")
        key(34, "i", flags: .command); try await pause()
        try check(window.firstResponder === editor, "Command-I focuses the prompt in full screen")
        window.toggleFullScreen(nil)
        try await SmokeTest.waitUntil { !window.styleMask.contains(.fullScreen) }
        try await pause(700)

        try await stress(model: model, output: output, check: check)
        try await CollectionScrollChecks.run(model: model, output: output, check: check)
        try await GroupInteractionChecks.run(model: model, output: output, check: check)
        model.open(originalURL)
        try await SmokeTest.waitUntil { model.video.ready || model.errorMessage != nil }
        try await pause(500)
        try check(SmokeTest.descendants(NSApp.keyWindow?.contentView).compactMap { $0 as? NoteTextView }.contains { $0.role.hasPrefix("group-") }, "Switching from a large to a small project resets collection scroll position")
    }

    static func stress(model: AppModel, output: URL, check: (Bool, String) throws -> Void) async throws {
        guard let sourceURL = model.projectURL, let imageFile = model.project?.boxes.first(where: { $0.imageFile != nil })?.imageFile, let videoPath = model.project?.videoPath else { throw ProjectError.invalid("Stress fixture missing") }
        let url = output.appendingPathComponent("1000 vboxes.framepad")
        var project = Project(title: "1,000 vboxes", videoPath: videoPath)
        var group = VBoxGroup(title: "One thousand image-backed moments", prompt: "A large group should be as comfortable to use as a small one.")
        for i in 0..<1000 {
            group.boxes.append(VBox(time: FrameTime(value: Int64(i * 6), timescale: 1000), frameIndex: i / 9, prompt: "Observation \(i + 1) · A detailed note for this moment.", imageFile: "stress-\(i).png"))
        }
        project.items = [.group(group)]
        try ProjectStore.create(project, at: url)
        for i in 0..<1000 {
            // Unique image URLs exercise cache cardinality; hard links keep test fixtures small.
            try FileManager.default.linkItem(at: ProjectStore.captureURL(imageFile, in: sourceURL), to: ProjectStore.captureURL("stress-\(i).png", in: url))
        }
        _ = model.flush(); await ThumbnailLoader.shared.clear()
        let began = Date()
        model.open(url)
        try await SmokeTest.waitUntil { model.video.ready || model.errorMessage != nil }
        try await pause(500)
        let firstDecodeCount = await ThumbnailLoader.shared.decodeCount
        try check(model.boxCount == 1000 && model.collectionRows.count == 1002, "1,000 grouped image vboxes load as individually virtualized rows")
        try check(firstDecodeCount < 100, "Opening a 1,000-image group decodes only a small visible subset (\(firstDecodeCount) thumbnails)")
        var maximumTickDelay = 0.0
        for index in [0, 250, 500, 750, 999] {
            let tick = Date()
            model.requestCollectionScroll(to: group.boxes[index].id)
            try await pause(100)
            maximumTickDelay = max(maximumTickDelay, Date().timeIntervalSince(tick) - 0.1)
            try await pause(200)
        }
        let cached = await ThumbnailLoader.shared.cachedBytes
        let limit = ThumbnailLoader.shared.byteLimit
        try check(cached <= limit, "Thumbnail cache remains within its 32 MiB budget")
        try check(maximumTickDelay < 0.5, "UI event loop remains responsive while scrolling the 1,000-vbox collection")
        model.video.seek(1.2); model.prompt = "Added after one thousand vboxes"
        let saveStart = Date()
        model.saveBox(); try await SmokeTest.waitUntil { !model.isSaving }
        let captureElapsed = Date().timeIntervalSince(saveStart)
        try check(model.boxCount == 1001, "Saving a new captured vbox succeeds with 1,000 existing images")
        model.undo(); try check(model.boxCount == 1000, "Undo addition with 1,000 existing vboxes")
        _ = model.flush()
        let reopened = try ProjectStore.load(at: url)
        try check(reopened.boxes.count == 1000, "All 1,000 vboxes persist and reload")
        let report = "Image-backed vboxes: 1000\nGroup size: 1000\nInitially decoded thumbnails: \(firstDecodeCount)\nCached thumbnail bytes: \(cached) / \(limit)\nMaximum measured run-loop delay: \(maximumTickDelay) seconds\nFrame capture and insertion elapsed: \(captureElapsed) seconds\nScenario elapsed: \(Date().timeIntervalSince(began)) seconds\nFixture: 1000 unique paths hard-linked to a generated source PNG; no original videos copied.\n"
        try report.write(to: output.appendingPathComponent("performance.txt"), atomically: true, encoding: .utf8)
        AppDelegate.snapshot(path: output.appendingPathComponent("1000-vboxes.png").path)
    }
    static func key(_ code: UInt16, _ characters: String, flags: NSEvent.ModifierFlags = []) {
        SmokeTest.postKey(code, characters, down: true, flags: flags); SmokeTest.postKey(code, characters, down: false, flags: flags)
    }
    static func pause(_ milliseconds: Int = 150) async throws { try await Task.sleep(for: .milliseconds(milliseconds)) }
    static func drag(_ view: NSView, from start: CGPoint, to end: CGPoint) async throws {
        func post(_ type: NSEvent.EventType, _ point: CGPoint) {
            let position = view.convert(point, to: nil)
            if let event = NSEvent.mouseEvent(with: type, location: position, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: view.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { NSApp.postEvent(event, atStart: false) }
        }
        post(.leftMouseDown, start); try await pause(60)
        post(.leftMouseDragged, end); try await pause(60)
        post(.leftMouseUp, end); try await pause()
    }
}
