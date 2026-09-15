import AppKit
import AVFoundation
import CoreImage
import FramepadCore

@MainActor enum CaptureChecks {
    static func run(model: AppModel, output: URL, check: (Bool, String) throws -> Void) async throws {
        guard let item = model.video.player.currentItem else { throw ProjectError.invalid("No player item") }
        let probe = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(probe); defer { item.remove(probe) }
        let frames = model.video.frameIndex.frames
        for index in [1, 2, 3, 5, 10, 17, 18, 19, 20, 37, 65] {
            model.video.pause(); model.video.seek(frames[index].seconds)
            try await SmokeTest.waitUntil { abs(model.video.player.currentTime().seconds - frames[index].seconds) < 0.00001 }
            try await RevisionChecks.pause(120)
            let displayed = try await displayedFrame(probe, player: model.video.player)
            model.prompt = "Paused capture \(index)"
            model.saveBox(); try await SmokeTest.waitUntil { !model.isSaving }
            guard let box = model.project?.boxes.last else { throw ProjectError.invalid(model.errorMessage ?? "Capture missing") }
            let pixels = try savedFrame(box, in: model.projectURL!)
            try check(pixels == displayed.index && box.frameIndex == displayed.index,
                      "Paused capture matches displayed pixels and frame index at fractional boundary \(index) (displayed \(displayed.index), saved \(pixels), metadata \(box.frameIndex))")
        }
        for index in [17, 20, 37] {
            for milliseconds in [35, 75, 150] {
                model.video.seek(frames[index].seconds)
                try await RevisionChecks.pause(180)
                model.video.toggle(); try await RevisionChecks.pause(milliseconds); model.video.pause()
                try await RevisionChecks.pause(180)
                let displayed = try await displayedFrame(probe, player: model.video.player)
                model.saveBox(); try await SmokeTest.waitUntil { !model.isSaving }
                guard let box = model.project?.boxes.last else { throw ProjectError.invalid("Playback capture missing") }
                try check(box.frameIndex == displayed.index && (try savedFrame(box, in: model.projectURL!)) == displayed.index,
                          "Capture after \(milliseconds) ms playback from frame \(index) matches the paused display and exact source frame")
            }
        }
        // Simulate a busy UI queue while the media clock continues to advance.
        model.video.seek(frames[24].seconds)
        try await RevisionChecks.pause(200)
        model.video.toggle(); try await RevisionChecks.pause(150)
        occupyMainThread()
        let live = model.video.player.currentTime().seconds
        let expected = model.video.frameIndex.index(at: live)!
        model.saveBox(); try await SmokeTest.waitUntil { !model.isSaving }
        guard let playingBox = model.project?.boxes.last else { throw ProjectError.invalid("Live capture missing") }
        try check(abs(playingBox.time.seconds - frames[expected].seconds) < 0.000001,
                  "Capture uses the live player clock when the UI time observer is delayed (expected \(expected), saved \(playingBox.frameIndex))")
        try check(try savedFrame(playingBox, in: model.projectURL!) == playingBox.frameIndex, "Live captured pixels agree with saved frame metadata")

        for index in [14, 31, 62] {
            model.video.seek(frames[8].seconds); model.video.seek(frames[90].seconds); model.video.seek(frames[index].seconds)
            model.saveBox(); try await SmokeTest.waitUntil { !model.isSaving }
            guard let box = model.project?.boxes.last else { throw ProjectError.invalid("Rapid-seek capture missing") }
            try check(box.frameIndex == index && (try savedFrame(box, in: model.projectURL!)) == index, "Immediate save after rapid seeks captures the final requested frame \(index)")
            try await RevisionChecks.pause(150)
            try check(model.video.currentFrame == index, "Late seek and observer callbacks do not change the saved selection \(index)")
        }
    }
    private static func occupyMainThread() { Thread.sleep(forTimeInterval: 0.23) }
    private static func displayedFrame(_ probe: AVPlayerItemVideoOutput, player: AVPlayer) async throws -> (index: Int, time: CMTime) {
        for _ in 0..<100 {
            var presentation = CMTime.invalid
            if let buffer = probe.copyPixelBuffer(forItemTime: player.currentTime(), itemTimeForDisplay: &presentation) {
                let image = CIImage(cvPixelBuffer: buffer)
                guard let cg = CIContext().createCGImage(image, from: image.extent) else { break }
                return (try frameNumber(cg), presentation)
            }
            try await RevisionChecks.pause(20)
        }
        throw ProjectError.invalid("No decoded player frame available for comparison")
    }
    private static func savedFrame(_ box: VBox, in url: URL) throws -> Int {
        guard let file = box.imageFile,
              let source = CGImageSourceCreateWithURL(ProjectStore.captureURL(file, in: url) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ProjectError.invalid("Saved image missing") }
        return try frameNumber(image)
    }
    private static func frameNumber(_ image: CGImage) throws -> Int {
        var result = 0
        for bit in 0..<7 {
            guard let sample = image.cropping(to: CGRect(x: bit * 128 + 48, y: 24, width: 32, height: 16)) else { throw ProjectError.invalid("Frame barcode missing") }
            var pixel = [UInt8](repeating: 0, count: 4)
            guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ProjectError.invalid("No comparison context") }
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            if pixel[0] > 127 { result |= 1 << bit }
        }
        return result
    }
}
