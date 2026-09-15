import AppKit
import AVFoundation
import FramepadCore

@MainActor enum SmokeTest {
    static func run(model: AppModel) async {
        let output: URL
        if let i = CommandLine.arguments.firstIndex(of: "--test-output"), CommandLine.arguments.count > i + 1 { output = URL(fileURLWithPath: CommandLine.arguments[i + 1]) }
        else { output = FileManager.default.temporaryDirectory.appendingPathComponent("Framepad-validation-\(UUID().uuidString)") }
        var checks: [String] = []
        func check(_ condition: @autoclosure () -> Bool, _ name: String) throws {
            guard condition() else { throw ProjectError.invalid("FAIL: \(name)") }
            checks.append("PASS: \(name)")
            try (checks.joined(separator: "\n") + "\n").write(to: output.appendingPathComponent("results.txt"), atomically: true, encoding: .utf8)
        }
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            if let i = CommandLine.arguments.firstIndex(of: "--inspect-project"), CommandLine.arguments.count > i + 1 {
                let source = URL(fileURLWithPath: (CommandLine.arguments[i + 1] as NSString).expandingTildeInPath)
                try await ProjectCaptureDiagnostics.run(model: model, source: source, output: output, check: { condition, name in try check(condition, name) })
                try (checks.joined(separator: "\n") + "\n\nALL \(checks.count) CHECKS PASSED\n").write(to: output.appendingPathComponent("results.txt"), atomically: true, encoding: .utf8)
                NSApp.terminate(nil); return
            }
            let movie = output.appendingPathComponent("Coastal light.mov")
            let captureChecks = CommandLine.arguments.contains("--capture-checks-only")
            let offset = captureChecks ? CMTime(value: 7200, timescale: 90000) : CMTime.zero
            let times = try await makeVideo(at: movie, fractionalTiming: captureChecks, timelineOffset: offset)
            let projectURL = output.appendingPathComponent("Coastal study.framepad")
            try ProjectStore.create(Project(title: "Coastal study", videoPath: movie.path), at: projectURL)
            if captureChecks {
                // Seed the pre-1.6 cache format with raw media times. Opening
                // must rebuild it instead of keeping the old shifted index.
                let attributes = try FileManager.default.attributesOfItem(atPath: movie.path)
                let stale = IndexedVideo(size: (attributes[.size] as! NSNumber).int64Value,
                                         modified: attributes[.modificationDate] as! Date, path: movie.path,
                                         index: FrameIndex(frames: times.map { let t = CMTimeSubtract($0, offset); return FrameTime(value: t.value, timescale: t.timescale) }))
                let data = try PropertyListEncoder().encode(stale)
                var plist = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
                plist.removeValue(forKey: "version")
                try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0).write(to: projectURL.appendingPathComponent("frames.plist"))
            }
            model.load(try ProjectStore.load(at: projectURL), from: projectURL)
            try await waitUntil { model.video.ready || model.errorMessage != nil }
            try check(model.video.ready, "Video loads and becomes ready: \(model.errorMessage ?? "ready")")
            try check(model.video.frameIndex.frames.count == times.count, "Exact sample count for variable-frame-rate video")
            if captureChecks {
                let track = try await model.video.asset!.loadTracks(withMediaType: .video).first!
                let segments = try await track.load(.segments)
                try check(segments.contains { !$0.isEmpty && CMTimeCompare($0.timeMapping.source.start, $0.timeMapping.target.start) != 0 }, "Capture fixture has a media-to-playback timeline offset")
                try check(zip(model.video.frameIndex.frames, times).allSatisfy { CMTimeCompare(CMTime(value: $0.0.value, timescale: $0.0.timescale), $0.1) == 0 }, "Legacy cache is rebuilt with exact playback timestamps, including the container edit")
                try await CaptureChecks.run(model: model, output: output, check: { condition, name in try check(condition, name) })
                try (checks.joined(separator: "\n") + "\n\nALL \(checks.count) CHECKS PASSED\n").write(to: output.appendingPathComponent("results.txt"), atomically: true, encoding: .utf8)
                NSApp.terminate(nil); return
            }
            for i in times.indices { try check(abs(model.video.frameIndex.frames[i].seconds - times[i].seconds) < 0.00001, "Presentation timestamp \(i)") }
            model.video.seek(2.175)
            model.prompt = "The shoreline creates a natural leading line. Keep the quieter composition."
            model.crop = CropRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
            model.saveBox()
            try await waitUntil { !model.isSaving }
            try check(model.project?.boxes.count == 1, "Cropped frame and note saved: \(model.errorMessage ?? "OK")")
            guard let captured = model.project?.boxes.first, let file = captured.imageFile,
                  let source = CGImageSourceCreateWithURL(ProjectStore.captureURL(file, in: projectURL) as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ProjectError.invalid("Captured PNG missing") }
            try check(image.width == 640 && image.height == 360, "Normalized crop produces a 640 × 360 PNG from 1280 × 720")
            try check(captured.time == model.video.frameIndex.frames[captured.frameIndex], "Capture timestamp agrees with exact frame index")
            if CommandLine.arguments.contains("--group-checks-only") {
                let boxes = (0..<40).map { i in VBox(time: model.video.frameIndex.frames[i], frameIndex: i, prompt: "Moment \(i + 1)", imageFile: file) }
                model.project?.items = [.group(VBoxGroup(title: "Group interactions", boxes: boxes))]
                try await Task.sleep(for: .milliseconds(350))
                try await GroupInteractionChecks.run(model: model, output: output, check: { condition, name in try check(condition, name) })
                try (checks.joined(separator: "\n") + "\n\nALL \(checks.count) CHECKS PASSED\n").write(to: output.appendingPathComponent("results.txt"), atomically: true, encoding: .utf8)
                NSApp.terminate(nil); return
            }
            model.video.seek(0.19); model.prompt = "Let the opening breathe before the first cut."
            model.saveBox(promptOnly: true); try await waitUntil { !model.isSaving }
            try check(model.project?.boxes.count == 2 && model.project?.boxes.last?.imageFile == nil, "Prompt-only vbox has a timestamp and no frame image")
            let note = model.project!.boxes.last!
            model.createGroup(); let group = model.selectedGroupID!
            model.project?.updateGroup(group, title: "01 · Composition", prompt: "Look for the rhythm between the coastline and the open water.")
            model.moveBox(captured.id, to: group); model.moveBox(note.id, to: group)
            try check(model.project?.boxes.map(\.id) == [note.id, captured.id], "Moving older vboxes into a new group sorts them by timestamp")
            model.video.seek(3.28); model.prompt = "A little more space around the horizon."
            model.saveBox(); try await waitUntil { !model.isSaving }
            try check(model.project?.boxes.count == 3 && model.project?.group(containing: model.project!.boxes.last!.id) == group, "Saving into selected group")
            model.returnToDraft(clearGroup: true)
            model.video.seek(1.375); model.prompt = "A draft I should get back"; model.crop = CropRect(x: 0.1, y: 0.1, width: 0.7, height: 0.7)
            let draftCrop = model.crop
            model.selectBox(captured)
            try check(model.prompt == captured.prompt && abs(model.video.position - captured.time.seconds) < 0.000001, "Selecting vbox loads its prompt and timestamp")
            model.prompt = "Edited description survives selection changes."
            model.returnToDraft(clearGroup: true)
            try check(model.prompt == "A draft I should get back" && model.crop == draftCrop && abs(model.video.position - 1.375) < 0.000001, "Deselect restores previous draft, crop, and playhead")
            try check(model.project?.box(captured.id)?.prompt == "Edited description survives selection changes.", "Vbox description edits autosave on deselection")
            model.moveBox(note.id, to: nil)
            try check(model.project?.items.last?.id == note.id && model.project?.group(containing: note.id) == nil, "Drop outside group moves vbox to end")
            model.undo()
            try check(model.project?.group(containing: note.id) == group, "Collection undo restores group membership")
            model.deleteBox(note.id); try check(model.project?.box(note.id) == nil, "Delete vbox")
            model.undo(); try check(model.project?.box(note.id) != nil, "Undo deletion preserves vbox")
            model.video.seek(0.5); model.video.skip(3); try check(abs(model.video.position - 3.5) < 0.000001, "Forward key target updates synchronously")
            model.video.skip(-3); try check(abs(model.video.position - 0.5) < 0.000001, "Backward key target updates synchronously")
            model.video.skip(-100); try check(model.video.position == 0, "Seek clamps at video start")
            model.video.skip(100); try check(model.video.position == model.video.duration, "Seek clamps at video end")
            model.video.seek(2.4); model.prompt = "A draft I should get back"; model.crop = nil
            try check(model.flush(), "Project flush succeeds")
            let saved = try ProjectStore.load(at: projectURL)
            try check(saved.boxes.count == 3 && saved.draft == model.prompt, "Reopening project preserves annotations and unsaved draft")
            try check(saved.videoPath == movie.path, "Source video remains a reference outside the project")
            model.goHome(); try await Task.sleep(for: .milliseconds(200)); model.open(projectURL)
            try await waitUntil { model.video.ready || model.errorMessage != nil }
            try check(model.video.ready && model.prompt == saved.draft, "Close and reopen restores draft and indexed media")
            // Exercise the actual local keyboard event monitor, including text-entry protection.
            NSApp.keyWindow?.makeFirstResponder(nil)
            model.video.pause(); model.video.seek(0.2)
            postKey(124, "\u{F703}", down: true); postKey(124, "\u{F703}", down: false)
            try await Task.sleep(for: .milliseconds(120))
            try check(abs(model.video.position - 3.2) < 0.01, "Right-arrow event seeks exactly three seconds")
            postKey(123, "\u{F702}", down: true); postKey(123, "\u{F702}", down: false)
            try await Task.sleep(for: .milliseconds(120))
            try check(abs(model.video.position - 0.2) < 0.01, "Left-arrow event seeks exactly three seconds")
            postKey(49, " ", down: true); postKey(49, " ", down: false)
            try await Task.sleep(for: .milliseconds(350))
            try check(model.video.playing && model.video.position > 0.2, "Space event starts actual video playback")
            postKey(49, " ", down: true); postKey(49, " ", down: false)
            try await Task.sleep(for: .milliseconds(100))
            try check(!model.video.playing, "Space event pauses video playback")
            model.video.seek(0)
            postKey(124, "\u{F703}", down: true)
            try await Task.sleep(for: .milliseconds(460))
            postKey(124, "\u{F703}", down: false)
            try await Task.sleep(for: .milliseconds(100))
            try check(model.video.position > 6, "Holding arrow repeats seeking without relying on system key-repeat delay")
            model.video.seek(1.6)
            postKey(8, "c", down: true, flags: [.command, .shift]); postKey(8, "c", down: false, flags: [.command, .shift])
            try await Task.sleep(for: .milliseconds(100))
            try check(model.cropMode, "Command-Shift-C enables crop selection")
            postKey(13, "w", down: true, flags: .command); postKey(13, "w", down: false, flags: .command)
            try await Task.sleep(for: .milliseconds(100))
            try check(!model.cropMode && model.crop == nil, "Command-W clears crop selection without closing the app")
            let surfaces = descendants(NSApp.keyWindow?.contentView).compactMap { $0 as? PlayerSurface }
            try await waitUntil { surfaces.first?.playerLayer.isReadyForDisplay == true }
            try check(surfaces.first?.playerLayer.isReadyForDisplay == true, "AVPlayerLayer has a decoded video frame ready for display")
            if let editor = descendants(NSApp.keyWindow?.contentView).compactMap({ $0 as? NSTextView }).first {
                model.prompt = "Typing"; try await Task.sleep(for: .milliseconds(100))
                NSApp.keyWindow?.makeFirstResponder(editor)
                editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
                postKey(49, " ", down: true); postKey(49, " ", down: false)
                try await Task.sleep(for: .milliseconds(100))
                try check(!model.video.playing && model.prompt == "Typing ", "Space inserts text instead of playing while the description editor is focused")
            } else { throw ProjectError.invalid("Description editor could not be found for the keyboard test") }
            NSApp.keyWindow?.makeFirstResponder(nil)
            model.prompt = "Shortcut-only note"
            let beforeShortcuts = model.project!.boxes.count
            postKey(44, "/", down: true, flags: .command); postKey(44, "/", down: false, flags: .command)
            try await waitUntil { !model.isSaving && model.project!.boxes.count == beforeShortcuts + 1 }
            try check(model.project?.boxes.last?.imageFile == nil && model.project?.boxes.last?.prompt == "Shortcut-only note", "Command-slash event saves only the prompt")
            model.prompt = "Shortcut capture"
            postKey(36, "\r", down: true, flags: .command); postKey(36, "\r", down: false, flags: .command)
            try await waitUntil { !model.isSaving && model.project!.boxes.count == beforeShortcuts + 2 }
            try check(model.project?.boxes.last?.imageFile != nil, "Command-Return event saves a captured frame")
            model.undo(); model.undo()
            if let window = NSApp.keyWindow {
                window.setContentSize(NSSize(width: 1040, height: 700))
                try await Task.sleep(for: .milliseconds(350))
                AppDelegate.snapshot(path: output.appendingPathComponent("compact-workspace.png").path)
                window.setContentSize(NSSize(width: 1400, height: 872))
                try await Task.sleep(for: .milliseconds(200))
                try check(window.contentView!.bounds.width == 1400, "Workspace renders at minimum and full window sizes")
            }
            try await RevisionChecks.run(model: model, output: output, check: { condition, name in try check(condition, name) })
            // Leave a useful review state for the workspace screenshot.
            model.prompt = "The light shifts here. Give this moment a little room before the next cut."
            model.video.seek(2.4); model.selectedGroupID = group
            try await Task.sleep(for: .milliseconds(700))
            AppDelegate.snapshot(path: output.appendingPathComponent("workspace.png").path)
            model.goHome()
            try await Task.sleep(for: .milliseconds(300))
            AppDelegate.snapshot(path: output.appendingPathComponent("home.png").path)
            checks.append("PASS: Native application lifecycle and view rendering")
            try (checks.joined(separator: "\n") + "\n\nALL \(checks.count) CHECKS PASSED\n").write(to: output.appendingPathComponent("results.txt"), atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        } catch {
            AppDelegate.snapshot(path: output.appendingPathComponent("failure.png").path)
            let report = checks.joined(separator: "\n") + "\n\n\(error.localizedDescription)\n"
            try? report.write(to: output.appendingPathComponent("results.txt"), atomically: true, encoding: .utf8)
            model.errorMessage = nil; model.isSaving = false
            NSApp.terminate(nil)
        }
    }

    static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<600 { if condition() { return }; try await Task.sleep(for: .milliseconds(50)) }
        throw ProjectError.invalid("Integration check timed out")
    }

    static func postKey(_ code: UInt16, _ characters: String, down: Bool, flags: NSEvent.ModifierFlags = []) {
        guard let event = NSEvent.keyEvent(with: down ? .keyDown : .keyUp, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: NSApp.keyWindow?.windowNumber ?? 0, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else { return }
        NSApp.postEvent(event, atStart: false)
    }
    static func descendants(_ view: NSView?) -> [NSView] {
        guard let view else { return [] }; return [view] + view.subviews.flatMap { descendants($0) }
    }

    static func makeVideo(at url: URL, fractionalTiming: Bool = false, timelineOffset: CMTime = .zero) async throws -> [CMTime] {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1280, AVVideoHeightKey: 720])
        // The default 600 Hz track clock would quantize away the submillisecond
        // regression boundaries before the app ever reads the generated video.
        if fractionalTiming { input.mediaTimeScale = 90000; writer.movieTimeScale = 90000 }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 1280, kCVPixelBufferHeightKey as String: 720, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ProjectError.invalid("Test writer failed") }
        writer.startSession(atSourceTime: .zero)
        var times: [CMTime] = []; var tick: Int64 = 0
        for i in 0..<120 {
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed { throw writer.error ?? ProjectError.invalid("Writer failed") }
                try await Task.sleep(for: .milliseconds(5))
            }
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw ProjectError.invalid("No pixel buffer") }
            CVPixelBufferLockBaseAddress(buffer, [])
            guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 1280, height: 720, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { throw ProjectError.invalid("No graphics context") }
            drawScene(context, phase: Double(i) / 120)
            if fractionalTiming {
                for bit in 0..<7 {
                    context.setFillColor((i & (1 << bit)) == 0 ? CGColor(gray: 0, alpha: 1) : CGColor(gray: 1, alpha: 1))
                    context.fill(CGRect(x: bit * 128, y: 0, width: 128, height: 64))
                    context.fill(CGRect(x: bit * 128, y: 656, width: 128, height: 64))
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            let time = CMTime(value: tick, timescale: fractionalTiming ? 90000 : 1000)
            let presentation = CMTimeAdd(time, timelineOffset)
            guard adaptor.append(buffer, withPresentationTime: presentation) else { throw writer.error ?? ProjectError.invalid("Append failed") }
            times.append(presentation)
            tick += fractionalTiming ? ((17...19).contains(i) ? 1 : (i % 7 == 2 ? 18018 : 3003)) : (i % 3 == 2 ? 80 : 40)
        }
        input.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? ProjectError.invalid("Test video could not be written") }
        return times
    }
    static func drawScene(_ c: CGContext, phase: Double) {
        let colors = [CGColor(red: 0.13, green: 0.26, blue: 0.29, alpha: 1), CGColor(red: 0.44, green: 0.58, blue: 0.52, alpha: 1)]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
        c.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1000, y: 720), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        for n in 0..<24 {
            let y = Double(n) * 38 - 100 + phase * 20
            c.beginPath(); c.move(to: CGPoint(x: 0, y: y))
            c.addCurve(to: CGPoint(x: 1280, y: y + 160), control1: CGPoint(x: 370, y: y + 80), control2: CGPoint(x: 800, y: y - 70))
            c.setStrokeColor(CGColor(red: 0.82, green: 0.91, blue: 0.82, alpha: 0.10)); c.setLineWidth(2); c.strokePath()
        }
        c.beginPath(); c.move(to: CGPoint(x: 0, y: 0)); c.addLine(to: CGPoint(x: 0, y: 540))
        c.addCurve(to: CGPoint(x: 810, y: 0), control1: CGPoint(x: 600, y: 560), control2: CGPoint(x: 120, y: 160))
        c.closePath(); c.setFillColor(CGColor(red: 0.75, green: 0.71, blue: 0.52, alpha: 1)); c.fillPath()
        c.beginPath(); c.move(to: CGPoint(x: 0, y: 0)); c.addLine(to: CGPoint(x: 0, y: 490))
        c.addCurve(to: CGPoint(x: 730, y: 0), control1: CGPoint(x: 540, y: 490), control2: CGPoint(x: 70, y: 150))
        c.closePath(); c.setFillColor(CGColor(red: 0.25, green: 0.34, blue: 0.25, alpha: 1)); c.fillPath()
        for i in 0..<60 {
            let x = Double((i * 83) % 300), y = Double((i * 61) % 340)
            c.setFillColor(CGColor(red: 0.14, green: 0.24, blue: 0.19, alpha: 0.45)); c.fillEllipse(in: CGRect(x: x, y: y, width: 36, height: 28))
        }
        c.setFillColor(CGColor(red: 0.95, green: 0.95, blue: 0.88, alpha: 0.8)); c.fillEllipse(in: CGRect(x: 930 + phase * 30, y: 340, width: 9, height: 28))
    }
}
