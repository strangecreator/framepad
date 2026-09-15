import AppKit
import AVFoundation
import Combine
import ImageIO
import FramepadCore

struct IndexedVideo: Codable {
    var version = 2
    var size: Int64
    var modified: Date
    var path: String
    var index: FrameIndex
}

@MainActor final class VideoEngine: ObservableObject {
    let player = AVPlayer()
    @Published var position = 0.0
    @Published var duration = 0.0
    @Published var playing = false
    @Published var ready = false
    @Published var status = "Opening video…"
    @Published var videoSize = CGSize(width: 16, height: 9)
    @Published var frameIndex = FrameIndex(frames: [])
    var asset: AVURLAsset?
    var errorHandler: ((String) -> Void)?
    var indexReadyHandler: ((FrameIndex) -> Void)?
    private var observer: Any?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var frameOutput: AVPlayerItemVideoOutput?
    private var seeking = false
    private var seekTarget = CMTime.zero
    private var generation = UUID()
    private var loadTask: Task<Void, Never>?
    var currentFrame: Int { frameIndex.index(at: position) ?? 0 }

    init() {
        player.actionAtItemEnd = .pause
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 60), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // A queued observer callback may describe an older frame. Read
                // the live clock, and never overwrite a paused or seeking frame.
                if self.playing, !self.seeking {
                    let seconds = self.player.currentTime().seconds
                    if seconds.isFinite { self.position = max(0, seconds) }
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let item = notification.object as? AVPlayerItem, item === self.player.currentItem else { return }
                self.playing = false; self.position = self.duration
            }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let item = notification.object as? AVPlayerItem, item === self.player.currentItem else { return }
                self.pause(); self.errorHandler?(item.error?.localizedDescription ?? "The video could not be played.")
            }
        }
    }

    func open(_ url: URL, projectURL: URL, at position: Double) {
        close()
        let token = generation
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        self.asset = asset
        loadTask = Task {
            do {
                let duration = try await asset.load(.duration)
                guard duration.seconds.isFinite, duration.seconds > 0 else { throw ProjectError.invalid("This video has no playable duration.") }
                guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw ProjectError.invalid("This file does not contain a video track.") }
                let size = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                guard token == generation else { return }
                let transformed = size.applying(transform)
                videoSize = CGSize(width: abs(transformed.width), height: abs(transformed.height))
                self.duration = duration.seconds
                let item = AVPlayerItem(asset: asset)
                let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
                item.add(output); frameOutput = output
                player.replaceCurrentItem(with: item)
                seek(position)
                status = "Indexing exact frames…"
                let index = try await Self.buildIndex(url: url, cacheURL: projectURL.appendingPathComponent("frames.plist"))
                guard token == generation else { return }
                guard !index.frames.isEmpty else { throw ProjectError.invalid("No decodable video frames were found.") }
                frameIndex = index; indexReadyHandler?(index); ready = true; status = "Ready"
                seek(self.position)
            } catch {
                guard token == generation else { return }
                status = "Video unavailable"; errorHandler?(error.localizedDescription)
            }
        }
    }

    nonisolated static func buildIndex(url: URL, cacheURL: URL?) async throws -> FrameIndex {
        let task = Task.detached(priority: .userInitiated) {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let modified = attributes[.modificationDate] as? Date ?? .distantPast
            if let cacheURL, let data = try? Data(contentsOf: cacheURL), let cache = try? PropertyListDecoder().decode(IndexedVideo.self, from: data),
               cache.version == 2, cache.size == size, cache.modified == modified, cache.path == url.path, !cache.index.frames.isEmpty { return cache.index }
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw ProjectError.invalid("No video track found.") }
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { throw ProjectError.invalid("This video format cannot be indexed.") }
            reader.add(output)
            guard reader.startReading() else { throw reader.error ?? ProjectError.invalid("Could not read this video.") }
            var times: [FrameTime] = []
            while let sample = output.copyNextSampleBuffer() {
                if Task.isCancelled { reader.cancelReading(); throw CancellationError() }
                let count = CMSampleBufferGetNumSamples(sample)
                guard count > 0 else { continue }
                var needed = 0
                // Output timing includes container edits (offsets and speed).
                // Raw compressed sample PTS is in the media timeline, which
                // can differ from the timeline used by AVPlayer and captures.
                CMSampleBufferGetOutputSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &needed)
                var entries = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: needed)
                let result = CMSampleBufferGetOutputSampleTimingInfoArray(sample, entryCount: needed, arrayToFill: &entries, entriesNeededOut: &needed)
                guard result == noErr else { throw ProjectError.invalid("Could not read exact frame timings.") }
                if entries.count == 1, count > 1 {
                    for i in 0..<count {
                        let t = CMTimeAdd(entries[0].presentationTimeStamp, CMTimeMultiply(entries[0].duration, multiplier: Int32(i)))
                        if t.isNumeric { times.append(FrameTime(value: t.value, timescale: t.timescale)) }
                    }
                } else {
                    for entry in entries where entry.presentationTimeStamp.isNumeric {
                        let t = entry.presentationTimeStamp
                        times.append(FrameTime(value: t.value, timescale: t.timescale))
                    }
                }
            }
            guard reader.status == .completed else { throw reader.error ?? ProjectError.invalid("Video indexing did not finish.") }
            let index = FrameIndex(frames: times)
            if let cacheURL {
                let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
                if let data = try? encoder.encode(IndexedVideo(size: size, modified: modified, path: url.path, index: index)) { try? data.write(to: cacheURL, options: .atomic) }
            }
            return index
        }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }

    func close() {
        generation = UUID(); loadTask?.cancel(); loadTask = nil
        // Closing must not start the exact-frame seek used for normal pauses.
        player.pause(); playing = false; player.currentItem?.cancelPendingSeeks()
        if let frameOutput { player.currentItem?.remove(frameOutput) }
        frameOutput = nil; player.replaceCurrentItem(with: nil)
        asset = nil; ready = false; position = 0; duration = 0; seeking = false; seekTarget = .zero
        frameIndex = FrameIndex(frames: []); status = "Opening video…"
    }
    func pause() {
        player.pause()
        if playing, !seeking {
            let seconds = player.currentTime().seconds
            if let index = displayedFrameIndex() {
                // Playback may retime output deadlines or leave the display
                // layer one refresh behind. Settle the paused preview on the
                // exact source frame so future crops, captures, and revisits
                // all show the same image.
                seek(frameIndex.frames[index].seconds)
            }
            else if seconds.isFinite { position = max(0, min(seconds, duration)) }
        }
        playing = false
    }
    func toggle() {
        guard duration > 0 else { return }
        if playing { pause() } else {
            if position >= duration - 0.001 { seek(0) }
            player.play(); playing = true
        }
    }
    func skip(_ delta: Double) { seek(position + delta) }
    func seek(_ seconds: Double) {
        guard duration > 0 else { return }
        let target = max(0, min(seconds, duration))
        if let index = frameIndex.index(at: target), abs(frameIndex.frames[index].seconds - target) < 0.0000001 {
            let frame = frameIndex.frames[index]
            seekTarget = CMTime(value: frame.value, timescale: frame.timescale)
        } else { seekTarget = CMTime(seconds: target, preferredTimescale: 1_000_000_000) }
        position = seekTarget.seconds
        if !seeking { performSeek() }
    }
    private func performSeek() {
        seeking = true
        let target = seekTarget, token = generation
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self, token == self.generation else { return }
                if CMTimeCompare(self.seekTarget, target) != 0 { self.performSeek() } else { self.seeking = false }
            }
        }
    }

    func freezeFrameForCapture() -> (time: FrameTime, index: Int)? {
        pause()
        // Keep the latest requested seek if decoding is still catching up.
        // After playback, the clock may lead the image still on screen. The
        // video output supplies that image's display deadline; map it back to
        // the source's exact playback PTS (deadlines can be retimed by AVPlayer).
        let clock = seeking ? seekTarget.seconds : player.currentTime().seconds
        guard let index = (!seeking ? displayedFrameIndex() : nil) ?? frameIndex.index(at: clock.isFinite ? clock : position) else { return nil }
        let frame = frameIndex.frames[index]
        seek(frame.seconds)
        return (frame, index)
    }

    private func displayedFrameIndex() -> Int? {
        var deadline = CMTime.invalid
        guard let frameOutput,
              frameOutput.copyPixelBuffer(forItemTime: player.currentTime(), itemTimeForDisplay: &deadline) != nil,
              deadline.isNumeric else { return nil }
        return frameIndex.index(at: deadline.seconds)
    }

    func capture(at time: FrameTime, crop: CropRect?) async throws -> (Data, FrameTime, Int) {
        guard let asset else { throw ProjectError.invalid("Open a video before saving a frame.") }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let result = try await generator.image(at: CMTime(value: time.value, timescale: time.timescale))
        guard CMTimeCompare(result.actualTime, CMTime(value: time.value, timescale: time.timescale)) == 0 else {
            throw ProjectError.invalid("The video decoder returned a different frame. The vbox was not changed; please try saving again.")
        }
        let data = try await Task.detached(priority: .userInitiated) {
            let image = try Self.cropped(result.image, to: crop)
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { throw ProjectError.invalid("Could not encode the captured frame.") }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw ProjectError.invalid("Could not encode the captured frame.") }
            return data as Data
        }.value
        let actual = result.actualTime
        return (data, FrameTime(value: actual.value, timescale: actual.timescale), frameIndex.index(at: actual.seconds) ?? 0)
    }
    nonisolated static func cropped(_ image: CGImage, to crop: CropRect?) throws -> CGImage {
        guard let crop else { return image }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect = CGRect(x: crop.x * Double(image.width), y: crop.y * Double(image.height), width: crop.width * Double(image.width), height: crop.height * Double(image.height)).integral.intersection(bounds)
        guard rect.width >= 1, rect.height >= 1, let result = image.cropping(to: rect) else { throw ProjectError.invalid("The crop is too small. Select a larger rectangle.") }
        return result
    }
}
