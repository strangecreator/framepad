import Foundation
import ImageIO

/// Serial decoding off the main actor, with a deterministic byte budget.
actor ThumbnailLoader {
    static let shared = ThumbnailLoader()
    private struct Entry { var image: CGImage; var cost: Int; var access: UInt64 }
    private var cache: [URL: Entry] = [:]
    private var clock: UInt64 = 0
    private(set) var cachedBytes = 0
    private(set) var decodeCount = 0
    let byteLimit = 32 * 1024 * 1024

    func image(at url: URL) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        clock += 1
        if var entry = cache[url] { entry.access = clock; cache[url] = entry; return entry.image }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 768,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        decodeCount += 1
        let cost = image.bytesPerRow * image.height
        while cachedBytes + cost > byteLimit, let oldest = cache.min(by: { $0.value.access < $1.value.access }) {
            cachedBytes -= oldest.value.cost; cache.removeValue(forKey: oldest.key)
        }
        if cost <= byteLimit { cache[url] = Entry(image: image, cost: cost, access: clock); cachedBytes += cost }
        return image
    }
    func clear() { cache.removeAll(); cachedBytes = 0; decodeCount = 0 }
}
