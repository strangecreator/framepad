import AppKit
import SwiftUI
import FramepadCore

struct CropInteraction: NSViewRepresentable {
    @ObservedObject var model: AppModel
    var videoRect: CGRect
    var videoSize: CGSize
    func makeNSView(context: Context) -> CropInteractionView { CropInteractionView() }
    func updateNSView(_ view: CropInteractionView, context: Context) {
        view.videoRect = videoRect; view.videoSize = videoSize; view.crop = model.crop
        view.canCreate = model.cropMode; view.enabled = model.video.ready && !model.isSaving
        if !view.canCreate || !view.enabled { view.cancelDrag() }
        view.onBegin = { model.video.pause(); model.cropMode = true }
        view.onChange = { model.crop = $0 }
        view.window?.invalidateCursorRects(for: view)
    }
}

final class CropInteractionView: NSView {
    var videoRect = CGRect.zero
    var videoSize = CGSize(width: 1, height: 1)
    var crop: CropRect?
    var canCreate = false
    var enabled = true
    var onBegin: (() -> Void)?
    var onChange: ((CropRect?) -> Void)?
    private var dragOrigin: CGPoint?
    private var originalCrop: CropRect?
    private var draggingHandle: CropHandle?
    private var tracking: NSTrackingArea?
    func cancelDrag() { dragOrigin = nil; draggingHandle = nil; originalCrop = nil }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var selectionRect: CGRect? {
        crop.map { CGRect(x: videoRect.minX + $0.x * videoRect.width, y: videoRect.minY + $0.y * videoRect.height, width: $0.width * videoRect.width, height: $0.height * videoRect.height) }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard enabled, bounds.contains(local), (canCreate && videoRect.contains(local)) || handle(at: local) != nil else { return nil }
        return self
    }
    func handle(at point: CGPoint) -> CropHandle? {
        guard let rect = selectionRect, rect.insetBy(dx: -7, dy: -7).contains(point) else { return nil }
        let left = abs(point.x - rect.minX) <= 7, right = abs(point.x - rect.maxX) <= 7
        let top = abs(point.y - rect.minY) <= 7, bottom = abs(point.y - rect.maxY) <= 7
        if left && top { return .topLeft }; if right && top { return .topRight }
        if left && bottom { return .bottomLeft }; if right && bottom { return .bottomRight }
        if left { return .left }; if right { return .right }; if top { return .top }; if bottom { return .bottom }
        return rect.contains(point) ? .move : nil
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func cursorUpdate(with event: NSEvent) { updateCursor(event) }
    override func mouseMoved(with event: NSEvent) { updateCursor(event) }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
    private func updateCursor(_ event: NSEvent) {
        guard enabled else { NSCursor.arrow.set(); return }
        let point = convert(event.locationInWindow, from: nil)
        switch handle(at: point) {
        case .left, .right: NSCursor.resizeLeftRight.set()
        case .top, .bottom: NSCursor.resizeUpDown.set()
        case .topLeft, .bottomRight: Self.diagonalDown.set()
        case .topRight, .bottomLeft: Self.diagonalUp.set()
        case .move: NSCursor.openHand.set()
        case nil: (canCreate && videoRect.contains(point) ? NSCursor.crosshair : NSCursor.arrow).set()
        }
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard enabled, videoRect.width > 0, videoRect.height > 0 else { return }
        draggingHandle = handle(at: point)
        guard draggingHandle != nil || (canCreate && videoRect.contains(point)) else { return }
        originalCrop = crop; dragOrigin = point; window?.makeFirstResponder(self); onBegin?()
        if draggingHandle == .move { NSCursor.closedHand.set() }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragOrigin else { return }
        let point = convert(event.locationInWindow, from: nil)
        let result: CropRect
        if let handle = draggingHandle, let originalCrop {
            result = CropGeometry.drag(originalCrop, handle: handle, dx: (point.x - start.x) / videoRect.width, dy: (point.y - start.y) / videoRect.height, minimumWidth: 2 / max(2, videoSize.width), minimumHeight: 2 / max(2, videoSize.height))
        } else {
            let end = CGPoint(x: min(max(point.x, videoRect.minX), videoRect.maxX), y: min(max(point.y, videoRect.minY), videoRect.maxY))
            result = CropRect(x: (min(start.x, end.x) - videoRect.minX) / videoRect.width, y: (min(start.y, end.y) - videoRect.minY) / videoRect.height, width: abs(end.x - start.x) / videoRect.width, height: abs(end.y - start.y) / videoRect.height)
        }
        crop = result; onChange?(result)
    }
    override func mouseUp(with event: NSEvent) {
        if dragOrigin != nil, let crop, crop.width * videoSize.width < 2 || crop.height * videoSize.height < 2 { self.crop = nil; onChange?(nil) }
        cancelDrag(); updateCursor(event)
    }
    private static let diagonalDown = diagonalCursor(mirrored: false)
    private static let diagonalUp = diagonalCursor(mirrored: true)
    private static func diagonalCursor(mirrored: Bool) -> NSCursor {
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { _ in
            let path = NSBezierPath()
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: mirrored ? 24 - y : y) }
            path.move(to: point(5, 5)); path.line(to: point(19, 19))
            path.move(to: point(5, 11)); path.line(to: point(5, 5)); path.line(to: point(11, 5))
            path.move(to: point(13, 19)); path.line(to: point(19, 19)); path.line(to: point(19, 13))
            path.lineCapStyle = .round; path.lineJoinStyle = .round
            NSColor.white.setStroke(); path.lineWidth = 4; path.stroke()
            NSColor.black.setStroke(); path.lineWidth = 2; path.stroke(); return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
    }
}
