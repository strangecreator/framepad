import AppKit
import AVFoundation
import CoreImage
import CryptoKit
import FramepadCore

/// Explicit diagnostic mode: the source is only read; saves, edits, and cache
/// rebuilding all happen inside a separate copy under the validation folder.
@MainActor enum ProjectCaptureDiagnostics {
    static func run(model: AppModel, source: URL, output: URL, check: (Bool, String) throws -> Void) async throws {
        let copy = output.appendingPathComponent("Inspection.framepad")
        try FileManager.default.copyItem(at: source, to: copy)
        let project = try ProjectStore.load(at: copy)
        let originalImages = try imageDigests(project: project, at: copy)
        model.load(project, from: copy)
        try await SmokeTest.waitUntil { model.video.ready || model.errorMessage != nil }
        guard model.video.ready, let asset = model.video.asset, let item = model.video.player.currentItem,
              let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ProjectError.invalid(model.errorMessage ?? "Inspection video unavailable")
        }
        var expected = project
        expected.reconcileFrameIndices(using: model.video.frameIndex)
        try check(model.project?.items == expected.items && model.prompt == project.draft && model.crop == project.draftCrop,
                  "Opening preserves existing annotations, images, timestamps, group order, and draft; only derived frame numbers are refreshed")
        let cache = try PropertyListDecoder().decode(IndexedVideo.self, from: Data(contentsOf: copy.appendingPathComponent("frames.plist")))
        try check(cache.version == 2 && cache.index.frames == model.video.frameIndex.frames, "Playback index is stored in the current cache format")

        var lines = ["Source project (read only): \(source.path)", "Working copy: \(copy.path)", "Video: \(project.videoPath)"]
        func log(_ line: String) throws {
            lines.append(line)
            try (lines.joined(separator: "\n") + "\n").write(to: output.appendingPathComponent("diagnostics.txt"), atomically: true, encoding: .utf8)
        }
        for segment in try await track.load(.segments) {
            let m = segment.timeMapping
            try log("EDIT source \(describe(m.source.start)) duration \(describe(m.source.duration)) -> target \(describe(m.target.start)) duration \(describe(m.target.duration))")
        }
        let reader = try AVAssetReader(asset: asset)
        let stream = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(stream) else { throw ProjectError.invalid("Cannot inspect compressed timing") }
        reader.add(stream)
        guard reader.startReading() else { throw reader.error ?? ProjectError.invalid("Cannot read compressed timing") }
        for n in 0..<5 {
            guard let sample = stream.copyNextSampleBuffer() else { break }
            try log("SAMPLE \(n) raw \(describe(CMSampleBufferGetPresentationTimeStamp(sample))) output \(describe(CMSampleBufferGetOutputPresentationTimeStamp(sample)))")
        }
        reader.cancelReading()

        let transform = try await track.load(.preferredTransform)
        let probe = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(probe); defer { item.remove(probe) }
        let arguments = CommandLine.arguments
        let extraTimes = arguments.indices.compactMap { i -> Double? in
            guard arguments[i] == "--inspect-time", arguments.count > i + 1 else { return nil }
            return Double(arguments[i + 1])
        }
        let existingTimes = arguments.contains("--inspect-only-extra-times") ? [] : project.boxes.map { $0.time.seconds } + [project.lastPosition]
        let targets = Set(existingTimes + extraTimes)
            .filter { $0.isFinite && $0 >= 0 && $0 < model.video.duration }.sorted()
        model.crop = nil
        func verifyNewCapture(_ label: String) async throws {
            let displayed = try await playerImage(probe, player: model.video.player, transform: transform)
            let clock = model.video.player.currentTime()
            let surface = SmokeTest.descendants(NSApp.keyWindow?.contentView).compactMap { $0 as? PlayerSurface }.first
            let layerImage = surface?.playerLayer.displayedPixelBuffer().flatMap { buffer -> CGImage? in
                let ci = CIImage(cvPixelBuffer: buffer).transformed(by: transform)
                return CIContext().createCGImage(ci, from: ci.extent)
            }
            let count = model.boxCount
            model.saveBox(); try await SmokeTest.waitUntil { !model.isSaving }
            guard model.errorMessage == nil, model.boxCount == count + 1, let box = model.project?.boxes.last else {
                throw ProjectError.invalid(model.errorMessage ?? "Expected a captured vbox in the working copy")
            }
            let saved = try savedImage(box, in: copy)
            let error = difference(displayed.image, saved)
            try log("\(label) clock \(describe(clock)) playerPTS \(describe(displayed.time)) saved \(box.time.value)/\(box.time.timescale) index \(box.frameIndex) player/saved MAE \(error) layer/saved MAE \(layerImage.map { difference($0, saved) } ?? -1)")
            if error >= 0.01 || (layerImage.map { difference($0, saved) >= 0.01 } ?? false) {
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
                for frame in model.video.frameIndex.frames where abs(frame.seconds - clock.seconds) < 0.2 {
                    let candidate = try await generator.image(at: CMTime(value: frame.value, timescale: frame.timescale))
                    try log("CANDIDATE \(describe(candidate.actualTime)) probe MAE \(difference(candidate.image, displayed.image)) layer MAE \(layerImage.map { difference(candidate.image, $0) } ?? -1)")
                }
            }
            try check(model.video.frameIndex.index(at: displayed.time.seconds) == box.frameIndex
                      && error < 0.01 && (layerImage.map { difference($0, saved) < 0.01 } ?? false)
                      && model.video.frameIndex.frames[box.frameIndex] == box.time,
                      "\(label): saved pixels, timestamp, and frame index match the independently decoded player frame")
            model.undo()
            try check(model.project?.items == expected.items, "\(label): undo preserves all existing vboxes and groups")
        }
        for seconds in targets {
            model.video.pause(); model.video.seek(seconds)
            try await SmokeTest.waitUntil { abs(model.video.player.currentTime().seconds - seconds) < 0.000001 }
            try await RevisionChecks.pause(180)
            try await verifyNewCapture("PAUSED \(seconds)")
        }
        for seconds in extraTimes.prefix(3) where seconds >= 0 && seconds < model.video.duration - 1 {
            model.video.seek(seconds)
            try await RevisionChecks.pause(180)
            model.video.toggle(); try await RevisionChecks.pause(150); model.video.pause()
            try await RevisionChecks.pause(100)
            try await verifyNewCapture("AFTER PLAYBACK from \(seconds)")
        }

        var editBox = expected.boxes.first { $0.imageFile != nil }
        if let i = arguments.firstIndex(of: "--inspect-vbox"), arguments.count > i + 1,
           let id = UUID(uuidString: arguments[i + 1]) {
            guard let requested = expected.box(id), requested.imageFile != nil else { throw ProjectError.invalid("Requested inspection vbox with image not found") }
            editBox = requested
        }
        if let original = editBox {
            model.selectBox(original)
            try await SmokeTest.waitUntil { abs(model.video.player.currentTime().seconds - original.time.seconds) < 0.000001 }
            try await RevisionChecks.pause(180)
            let displayed = try await playerImage(probe, player: model.video.player, transform: transform)
            let cropped = try VideoEngine.cropped(displayed.image, to: original.crop)
            try log("EXISTING VBOX \(original.id) original/player MAE \(difference(try savedImage(original, in: copy), cropped))")
            SmokeTest.postKey(36, "\r", down: true, flags: [.command])
            SmokeTest.postKey(36, "\r", down: false, flags: [.command])
            try await SmokeTest.waitUntil { model.errorMessage != nil || model.project?.box(original.id)?.imageFile != original.imageFile }
            try await SmokeTest.waitUntil { !model.isSaving }
            guard let edited = model.project?.box(original.id), model.errorMessage == nil else { throw ProjectError.invalid(model.errorMessage ?? "Edited vbox missing") }
            try check(edited.prompt == original.prompt && edited.crop == original.crop && edited.createdAt == original.createdAt
                      && model.project?.group(containing: edited.id) == expected.group(containing: original.id)
                      && difference(try savedImage(edited, in: copy), cropped) < 0.01
                      && model.video.frameIndex.index(at: displayed.time.seconds) == edited.frameIndex,
                      "Cmd-Return updates the existing vbox to the displayed frame while retaining its identity, description, crop, and group")
            model.undo(); model.returnToDraft(clearGroup: true)
        }
        try check(model.project?.items == expected.items, "All inspection edits undone; original annotations retained in the working copy")
        try check(try imageDigests(project: project, at: copy) == originalImages, "Every original captured PNG is byte-for-byte intact")
        try check(model.flush(), "Working copy saves successfully")
        let reopened = try ProjectStore.load(at: copy)
        try check(reopened.items == expected.items, "Existing annotations and corrected frame numbers survive a project round trip")
        let cached = try await VideoEngine.buildIndex(url: URL(fileURLWithPath: cache.path), cacheURL: copy.appendingPathComponent("frames.plist"))
        try check(cached.frames == model.video.frameIndex.frames, "Reopening reuses the corrected index without changing frame times")
        try log("Inspection complete; the original project was only read.")
    }

    private static func imageDigests(project: Project, at url: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        for file in Set(project.boxes.compactMap(\.imageFile)) {
            result[file] = SHA256.hash(data: try Data(contentsOf: ProjectStore.captureURL(file, in: url))).description
        }
        return result
    }
    private static func savedImage(_ box: VBox, in url: URL) throws -> CGImage {
        guard let file = box.imageFile,
              let source = CGImageSourceCreateWithURL(ProjectStore.captureURL(file, in: url) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ProjectError.invalid("Saved image missing") }
        return image
    }
    private static func describe(_ time: CMTime) -> String { "\(time.value)/\(time.timescale) (\(time.seconds))" }
    private static func playerImage(_ probe: AVPlayerItemVideoOutput, player: AVPlayer, transform: CGAffineTransform) async throws -> (image: CGImage, time: CMTime) {
        for _ in 0..<100 {
            var time = CMTime.invalid
            if let buffer = probe.copyPixelBuffer(forItemTime: player.currentTime(), itemTimeForDisplay: &time) {
                let ci = CIImage(cvPixelBuffer: buffer).transformed(by: transform)
                if let image = CIContext().createCGImage(ci, from: ci.extent) { return (image, time) }
            }
            try await RevisionChecks.pause(20)
        }
        throw ProjectError.invalid("No player frame available for inspection")
    }
    private static func difference(_ a: CGImage, _ b: CGImage) -> Double {
        guard a.width == b.width, a.height == b.height else { return .infinity }
        func pixels(_ image: CGImage) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: 128 * 72 * 4)
            let context = CGContext(data: &bytes, width: 128, height: 72, bitsPerComponent: 8, bytesPerRow: 128 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 128, height: 72)); return bytes
        }
        let x = pixels(a), y = pixels(b)
        return zip(x, y).enumerated().reduce(0.0) { sum, pair in pair.offset % 4 == 3 ? sum : sum + Double(abs(Int(pair.element.0) - Int(pair.element.1))) } / Double(128 * 72 * 3)
    }
}
