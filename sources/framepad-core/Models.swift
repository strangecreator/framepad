import Foundation

public struct FrameTime: Codable, Equatable, Sendable {
    public var value: Int64
    public var timescale: Int32
    public var seconds: Double { Double(value) / Double(timescale) }
    public init(value: Int64, timescale: Int32) { self.value = value; self.timescale = timescale }
}

public struct FrameIndex: Codable, Sendable {
    public var frames: [FrameTime]
    public init(frames: [FrameTime]) {
        self.frames = frames.filter { $0.timescale > 0 && $0.seconds >= 0 }.sorted { $0.seconds < $1.seconds }
    }
    public func index(at seconds: Double) -> Int? {
        guard !frames.isEmpty else { return nil }
        var low = 0, high = frames.count
        while low < high {
            let mid = (low + high) / 2
            if frames[mid].seconds <= seconds + 0.0000001 { low = mid + 1 } else { high = mid }
        }
        return max(0, low - 1)
    }
}

/// Coordinates are normalized to the displayed, orientation-corrected video, from its top-left.
public struct CropRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = min(max(x, 0), 1); self.y = min(max(y, 0), 1)
        self.width = min(max(width, 0), 1 - self.x)
        self.height = min(max(height, 0), 1 - self.y)
    }
}

public struct VBox: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var time: FrameTime
    public var frameIndex: Int
    public var prompt: String
    public var imageFile: String?
    public var crop: CropRect?
    public var createdAt: Date
    public init(id: UUID = UUID(), time: FrameTime, frameIndex: Int, prompt: String = "", imageFile: String? = nil, crop: CropRect? = nil) {
        self.id = id; self.time = time; self.frameIndex = frameIndex
        self.prompt = prompt; self.imageFile = imageFile; self.crop = crop; createdAt = Date()
    }
}

public struct VBoxGroup: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var prompt: String
    public var boxes: [VBox]
    public init(id: UUID = UUID(), title: String, prompt: String = "", boxes: [VBox] = []) {
        self.id = id; self.title = title; self.prompt = prompt; self.boxes = boxes
    }
}

public enum TimelineItem: Codable, Identifiable, Equatable, Sendable {
    case box(VBox)
    case group(VBoxGroup)
    public var id: UUID {
        switch self { case .box(let b): return b.id; case .group(let g): return g.id }
    }
}

public struct Project: Codable, Equatable, Sendable {
    public var version = 1
    public var id = UUID()
    public var title: String
    public var videoPath: String
    public var videoBookmark: Data?
    public var createdAt = Date()
    public var modifiedAt = Date()
    public var lastPosition: Double = 0
    public var draft = ""
    public var draftCrop: CropRect?
    public var items: [TimelineItem] = []
    public init(title: String, videoPath: String, videoBookmark: Data? = nil) {
        self.title = title; self.videoPath = videoPath; self.videoBookmark = videoBookmark
    }
    public var boxes: [VBox] {
        items.flatMap { switch $0 { case .box(let b): return [b]; case .group(let g): return g.boxes } }
    }
    public var groupCount: Int { items.filter { if case .group = $0 { return true }; return false }.count }
    /// Refresh derived frame numbers while retaining saved times, images,
    /// descriptions, membership, and order from existing projects.
    @discardableResult public mutating func reconcileFrameIndices(using index: FrameIndex) -> Bool {
        var changed = false
        func updated(_ box: VBox) -> VBox {
            guard let number = index.index(at: box.time.seconds), number != box.frameIndex else { return box }
            var result = box; result.frameIndex = number; changed = true; return result
        }
        items = items.map { item in
            switch item {
            case .box(let box): return .box(updated(box))
            case .group(var group): group.boxes = group.boxes.map(updated); return .group(group)
            }
        }
        return changed
    }
    public func box(_ id: UUID) -> VBox? {
        for item in items {
            switch item {
            case .box(let box) where box.id == id: return box
            case .group(let group): if let box = group.boxes.first(where: { $0.id == id }) { return box }
            default: break
            }
        }
        return nil
    }
    public func group(containing id: UUID) -> UUID? {
        items.first { if case .group(let g) = $0 { return g.boxes.contains { $0.id == id } }; return false }?.id
    }
    public mutating func insert(_ box: VBox, into groupID: UUID?) {
        if let groupID, let i = items.firstIndex(where: { $0.id == groupID }), case .group(var g) = items[i] {
            g.boxes.append(box); g.boxes.sort { $0.time.seconds == $1.time.seconds ? $0.createdAt < $1.createdAt : $0.time.seconds < $1.time.seconds }
            items[i] = .group(g)
        } else { items.append(.box(box)) }
    }
    public mutating func update(_ box: VBox) {
        for i in items.indices {
            switch items[i] {
            case .box(let b) where b.id == box.id: items[i] = .box(box); return
            case .group(var g):
                if let j = g.boxes.firstIndex(where: { $0.id == box.id }) {
                    g.boxes[j] = box
                    g.boxes.sort { $0.time.seconds == $1.time.seconds ? $0.createdAt < $1.createdAt : $0.time.seconds < $1.time.seconds }
                    items[i] = .group(g); return
                }
            default: break
            }
        }
    }
    @discardableResult public mutating func removeBox(_ id: UUID) -> VBox? {
        guard let existing = box(id) else { return nil }
        items.removeAll { if case .box(let b) = $0 { return b.id == id }; return false }
        for i in items.indices {
            if case .group(var g) = items[i] { g.boxes.removeAll { $0.id == id }; items[i] = .group(g) }
        }
        return existing
    }
    public mutating func moveBox(_ id: UUID, to groupID: UUID?) {
        // Validate the destination before removing anything.
        if let groupID, !items.contains(where: { if case .group(let g) = $0 { return g.id == groupID }; return false }) { return }
        guard let b = removeBox(id) else { return }
        insert(b, into: groupID)
    }
    public mutating func updateGroup(_ id: UUID, title: String? = nil, prompt: String? = nil) {
        guard let i = items.firstIndex(where: { $0.id == id }), case .group(var g) = items[i] else { return }
        if let title { g.title = title }; if let prompt { g.prompt = prompt }; items[i] = .group(g)
    }
    public mutating func ungroup(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), case .group(let g) = items[i] else { return }
        items.replaceSubrange(i...i, with: g.boxes.map(TimelineItem.box))
    }
}

public enum Timecode {
    public static func parts(_ seconds: Double) -> (main: String, milliseconds: String) {
        let total = Int64((max(0, seconds.isFinite ? seconds : 0) * 1000).rounded())
        return (String(format: "%02lld:%02lld:%02lld", total / 3_600_000, total / 60_000 % 60, total / 1000 % 60), String(format: ".%03lld", total % 1000))
    }
    public static func string(_ seconds: Double) -> String { let p = parts(seconds); return p.main + p.milliseconds }
}
