import AppKit
import FramepadCore

@MainActor enum CollectionScrollChecks {
    static func run(model: AppModel, output: URL, check: (Bool, String) throws -> Void) async throws {
        guard let source = model.projectURL, let image = model.project?.boxes.first?.imageFile,
              let videoPath = model.project?.videoPath else { throw ProjectError.invalid("Scroll fixture missing") }
        let url = output.appendingPathComponent("Collection scrolling.framepad")
        var project = Project(title: "Collection scrolling", videoPath: videoPath)
        let boxes = (0..<40).map { index in
            VBox(time: model.video.frameIndex.frames[index], frameIndex: index,
                 prompt: "Moment \(index + 1)", imageFile: "frame.png")
        }
        project.items = boxes.map { .box($0) }
        try ProjectStore.create(project, at: url)
        try FileManager.default.linkItem(at: ProjectStore.captureURL(image, in: source), to: ProjectStore.captureURL("frame.png", in: url))
        model.open(url)
        try await SmokeTest.waitUntil { model.video.ready || model.errorMessage != nil }
        try await RevisionChecks.pause(500)
        guard let window = NSApp.keyWindow,
              let collection = SmokeTest.descendants(window.contentView).compactMap({ $0 as? NSScrollView }).first(where: { $0.documentView?.isKind(of: NSTextView.self) == false && $0.frame.width < 520 }) else {
            throw ProjectError.invalid("Collection scroll view missing")
        }
        let target = boxes[20]
        model.requestCollectionScroll(to: boxes[22].id)
        try await RevisionChecks.pause(650)
        model.selectBox(target); try await RevisionChecks.pause(250)
        try check(model.collectionViewport.isVisible(target.id), "Edited vbox starts inside the collection viewport")
        let initialOrigin = collection.contentView.bounds.origin.y
        try await save(model: model)
        try check(abs(collection.contentView.bounds.origin.y - initialOrigin) < 2, "Saving an already visible vbox leaves the collection scroll position unchanged")

        // Even a partially visible card should not be repositioned by a save.
        guard let frame = model.collectionViewport.rows[target.id.uuidString] else { throw ProjectError.invalid("Visible row geometry missing") }
        collection.documentView?.scroll(CGPoint(x: 0, y: collection.contentView.bounds.origin.y + frame.minY + frame.height / 2))
        try await RevisionChecks.pause(350)
        let partialFrame = model.collectionViewport.rows[target.id.uuidString] ?? .zero
        try check(model.collectionViewport.isVisible(target.id) && partialFrame.minY < 0 && partialFrame.maxY > 0, "Viewport recognizes a partially visible edited card")
        let partialOrigin = collection.contentView.bounds.origin.y
        try await save(model: model)
        try check(abs(collection.contentView.bounds.origin.y - partialOrigin) < 2, "Saving a partially visible vbox preserves scroll position")

        for destination in [35, 4] {
            model.requestCollectionScroll(to: boxes[destination].id)
            try await RevisionChecks.pause(650)
            try check(!model.collectionViewport.isVisible(target.id), "Edited vbox is offscreen before save from row \(destination)")
            try await save(model: model)
            let viewport = model.collectionViewport
            let center = viewport.rows[target.id.uuidString]?.midY ?? -.infinity
            try check(viewport.isVisible(target.id) && abs(center - viewport.bounds.midY) < 3, "Saving an offscreen vbox reveals it at the collection center from row \(destination)")
        }
        AppDelegate.snapshot(path: output.appendingPathComponent("centered-edited-vbox.png").path)

        model.selectBox(boxes[0]); model.requestCollectionScroll(to: boxes[35].id)
        try await RevisionChecks.pause(650)
        try await save(model: model)
        try check(model.collectionViewport.isVisible(boxes[0].id) && collection.contentView.bounds.origin.y < 2, "Revealing the first vbox clamps to the top when centering is impossible")

        // Repeat with the same cards inside a group, where header/footer rows and
        // timestamp sorting must not change visibility or centering behavior.
        model.returnToDraft(clearGroup: true)
        var group = VBoxGroup(title: "Grouped scrolling")
        group.boxes = model.project!.boxes
        model.project?.items = [.group(group)]
        model.requestCollectionScroll(to: group.boxes[22].id)
        try await RevisionChecks.pause(650)
        model.selectBox(model.project!.box(target.id)!); try await RevisionChecks.pause(250)
        let groupedOrigin = collection.contentView.bounds.origin.y
        try check(model.collectionViewport.isVisible(target.id), "Grouped edited vbox starts inside the viewport")
        try await save(model: model)
        try check(abs(collection.contentView.bounds.origin.y - groupedOrigin) < 2, "Saving a visible grouped vbox preserves scroll position")
        model.requestCollectionScroll(to: group.boxes[35].id)
        try await RevisionChecks.pause(650)
        try await save(model: model)
        let viewport = model.collectionViewport
        try check(viewport.isVisible(target.id) && abs((viewport.rows[target.id.uuidString]?.midY ?? -.infinity) - viewport.bounds.midY) < 3, "Saving an offscreen grouped vbox centers it")
    }

    private static func save(model: AppModel) async throws {
        guard let id = model.selectedBoxID, let previousImage = model.project?.box(id)?.imageFile else { throw ProjectError.invalid("No selected capture") }
        RevisionChecks.key(36, "\r", flags: .command)
        try await SmokeTest.waitUntil { !model.isSaving && model.project?.box(id)?.imageFile != previousImage }
        try await RevisionChecks.pause(650)
    }
}
